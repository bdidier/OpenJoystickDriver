import Darwin
import Foundation

public final class LocalServiceRPCServer: @unchecked Sendable {
  public typealias Authentication = @Sendable (LocalSocketPeer) -> Bool
  public typealias Completion = @Sendable (LocalServiceRPCResponse) -> Void
  public typealias Handler = @Sendable (LocalServiceRPCRequest, @escaping Completion) -> Void

  private let authentication: Authentication
  private let handler: Handler
  private let socketPath: String
  private let stateLock = NSLock()
  private var listener: Listener?

  /// Runs once the accept loop has stopped and closed its descriptors; tests await it.
  package var acceptLoopDidExit: (@Sendable () -> Void)?

  /// One started server's sockets. The accept loop closes `socket` and `wakeRead`. Whoever clears
  /// `listener` closes `wakeWrite`: `stop()`, or the loop when it ends on its own. The loop sees
  /// the hang-up of `wakeRead` when `wakeWrite` closes.
  private struct Listener {
    let socket: Int32
    let wakeRead: Int32
    let wakeWrite: Int32
  }

  /// What the accept loop does after `accept` fails with an error number.
  package enum AcceptFailure: Equatable, Sendable {
    /// The connection was dropped before it was accepted; accept the next one.
    case skip
    /// The process or system is out of descriptors or memory. Connections wait in the queue;
    /// the loop reports the reason, waits and accepts again.
    case waitForResources
    /// The listening socket is unusable, so the server ends.
    case fatal

    package init(errno code: Int32) {
      switch code {
      case EINTR, ECONNABORTED: self = .skip
      case EMFILE, ENFILE, ENOBUFS, ENOMEM: self = .waitForResources
      default: self = .fatal
      }
    }
  }

  /// Seconds the accept loop waits after `AcceptFailure.waitForResources` before accepting again.
  package static let resourceWaitMilliseconds: Int32 = 500

  package static func acceptFailureMessage(_ code: Int32, action: AcceptFailure) -> String {
    let reason = String(cString: strerror(code))
    switch action {
    case .waitForResources:
      return "[LocalServiceRPCServer] Cannot accept connections (\(reason), errno \(code)); "
        + "retrying in \(resourceWaitMilliseconds) ms"
    default:
      return "[LocalServiceRPCServer] Stopped accepting connections (\(reason), errno \(code))"
    }
  }

  public convenience init(authentication: @escaping Authentication, handler: @escaping Handler) {
    self.init(
      socketPath: LocalServiceRPCTransport.defaultSocketPath,
      authentication: authentication,
      handler: handler
    )
  }

  package init(
    socketPath: String,
    authentication: @escaping Authentication,
    handler: @escaping Handler
  ) {
    self.socketPath = socketPath
    self.authentication = authentication
    self.handler = handler
  }

  public func start() throws {
    if stateLock.withLock({ listener != nil }) { throw LocalServiceRPCError.alreadyRunning }
    let path = socketPath
    try removeStaleSocket(at: path)
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    do {
      var address = try LocalServiceRPCTransport.socketAddress(path: path)
      let bindStatus = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(descriptor, $0, LocalServiceRPCTransport.socketAddressLength(path: path))
        }
      }
      guard bindStatus == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      guard Darwin.listen(descriptor, 16) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      var wake: [Int32] = [-1, -1]
      guard pipe(&wake) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      let started = Listener(socket: descriptor, wakeRead: wake[0], wakeWrite: wake[1])
      stateLock.withLock { listener = started }
      BlockingWork.detachThread(name: "com.openjoystickdriver.rpc.accept") { [weak self] in
        self?.acceptConnections(started)
      }
    } catch {
      Darwin.close(descriptor)
      unlink(path)
      throw error
    }
  }

  public func stop() {
    let stopped = stateLock.withLock { () -> Listener? in
      defer { listener = nil }
      return listener
    }
    guard let stopped else { return }
    // Closing the write end hangs up the read end, which wakes the accept loop to close the rest.
    Darwin.close(stopped.wakeWrite)
    unlink(socketPath)
  }

  /// Ends the server when the loop stops on its own: the loop owns `wakeWrite` then, unless
  /// `stop()` already took the listener.
  private func release(_ ended: Listener) {
    let owned = stateLock.withLock { () -> Bool in
      guard listener?.wakeWrite == ended.wakeWrite else { return false }
      listener = nil
      Darwin.close(ended.wakeWrite)
      return true
    }
    if owned { unlink(socketPath) }
  }

  private func acceptConnections(_ listener: Listener) {
    defer {
      release(listener)
      Darwin.close(listener.socket)
      Darwin.close(listener.wakeRead)
      acceptLoopDidExit?()
    }
    while true {
      var events = [
        pollfd(fd: listener.socket, events: Int16(POLLIN), revents: 0),
        pollfd(fd: listener.wakeRead, events: Int16(POLLIN), revents: 0),
      ]
      let ready = poll(&events, 2, -1)
      if ready < 0 {
        if errno == EINTR { continue }
        print(Self.acceptFailureMessage(errno, action: .fatal))
        return
      }
      if events[1].revents != 0 { return }
      guard events[0].revents & Int16(POLLIN) != 0 else {
        print(
          "[LocalServiceRPCServer] Stopped accepting connections "
            + "(listening socket poll events \(events[0].revents))"
        )
        return
      }
      let connection = Darwin.accept(listener.socket, nil, nil)
      guard connection >= 0 else {
        let code = errno
        let action = AcceptFailure(errno: code)
        switch action {
        case .skip: continue
        case .waitForResources:
          print(Self.acceptFailureMessage(code, action: action))
          // The wait ends early when the server stops.
          var wake = [pollfd(fd: listener.wakeRead, events: Int16(POLLIN), revents: 0)]
          _ = poll(&wake, 1, Self.resourceWaitMilliseconds)
          if wake[0].revents != 0 { return }
          continue
        case .fatal:
          print(Self.acceptFailureMessage(code, action: action))
          return
        }
      }
      BlockingWork.detach(label: "com.openjoystickdriver.rpc.connection") { [weak self] in
        self?.handleConnection(connection)
      }
    }
  }

  private func handleConnection(_ descriptor: Int32) {
    guard let peer = LocalSocketPeer.authenticated(descriptor) else {
      Darwin.close(descriptor)
      return
    }
    do {
      try LocalServiceRPCTransport.setTimeout(descriptor, seconds: 35)
      guard authentication(peer) else {
        let response = LocalServiceRPCResponse(
          result: nil,
          error: LocalServiceRPCError.peerRejected.localizedDescription,
          errorCode: .peerRejected
        )
        try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(response), to: descriptor)
        Darwin.close(descriptor)
        return
      }
      let data = try LocalServiceRPCTransport.receiveFrame(from: descriptor)
      let request = try JSONDecoder().decode(LocalServiceRPCRequest.self, from: data)
      handler(request) { response in
        defer { Darwin.close(descriptor) }
        guard let encoded = try? JSONEncoder().encode(response) else { return }
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
    } catch {
      let response = LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
      if let encoded = try? JSONEncoder().encode(response) {
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
      Darwin.close(descriptor)
    }
  }

  private func removeStaleSocket(at path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    if LocalServiceRPCClient.serverProcessIdentifier(socketPath: path) != nil {
      throw LocalServiceRPCError.alreadyRunning
    }
    var information = stat()
    guard lstat(path, &information) == 0 else { return }
    guard information.st_uid == geteuid(), information.st_mode & S_IFMT == S_IFSOCK else {
      throw LocalServiceRPCError.peerRejected
    }
    guard unlink(path) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
  }
}
