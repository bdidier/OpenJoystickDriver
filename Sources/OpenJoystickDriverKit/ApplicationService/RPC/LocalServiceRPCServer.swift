import Darwin
import Foundation

public final class LocalServiceRPCServer: @unchecked Sendable {
  public typealias Authentication = @Sendable (LocalSocketPeer) -> Bool
  public typealias Completion = @Sendable (LocalServiceRPCResponse) -> Void
  public typealias Handler = @Sendable (LocalServiceRPCRequest, @escaping Completion) -> Void

  private let authentication: Authentication
  private let handler: Handler
  package let socketPath: String
  private let stateLock = NSLock()
  private var listener: Listener?
  /// True while a `start()` call sets up the sockets, so a second call is refused.
  private var starting = false
  /// True when `stop()` ran while `starting`; `start()` stops the server it finished.
  private var stopRequested = false

  // The four hooks below belong to tests; set them before `start()`.
  /// Runs once the accept loop has stopped and closed its descriptors; tests await it.
  package var acceptLoopDidExit: (@Sendable () -> Void)?
  /// Takes one connection from the listening descriptor, as `accept` does; tests replace it to
  /// fail the call.
  package var acceptConnection: @Sendable (Int32) -> Int32 = { Darwin.accept($0, nil, nil) }
  /// Milliseconds the accept loop waits after running out of descriptors or memory.
  package var resourceWaitMilliseconds = AcceptFailure.resourceWaitMilliseconds
  /// Receives the accept loop's reports; they go to standard output.
  package var report: @Sendable (String) -> Void = { print($0) }
  private static let name = "LocalServiceRPCServer"

  /// One started server's sockets. The accept loop closes `socket` and `wakeRead`. Whoever clears
  /// `listener` closes `wakeWrite`: `stop()`, or the loop when it ends on its own. The loop sees
  /// the hang-up of `wakeRead` when `wakeWrite` closes. `id` tells servers apart that get the
  /// same descriptor numbers one after another.
  private struct Listener {
    let id = UUID()
    let socket: Int32
    let wakeRead: Int32
    let wakeWrite: Int32
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
    try stateLock.withLock {
      guard listener == nil, !starting else { throw LocalServiceRPCError.alreadyRunning }
      starting = true
    }
    do { try startReserved() } catch {
      stateLock.withLock {
        starting = false
        stopRequested = false
      }
      throw error
    }
    if stateLock.withLock({
      defer { stopRequested = false }; return stopRequested
    }) {
      stop()
    }
  }

  /// Call with the start slot reserved; the slot passes to `listener` when this returns.
  private func startReserved() throws {
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
      stateLock.withLock {
        listener = started
        starting = false
      }
      BlockingWork.detachThread(name: "com.openjoystickdriver.rpc.accept") { [weak self] in
        self?.acceptConnections(started)
      }
    } catch {
      Darwin.close(descriptor)
      unlink(path)
      throw error
    }
  }

  /// Stops the server. A call while `start()` still sets up the sockets takes effect as soon as
  /// that call returns.
  public func stop() {
    stateLock.withLock {
      guard let stopped = listener else {
        if starting { stopRequested = true }
        return
      }
      listener = nil
      // Closing the write end hangs up the read end, which wakes the accept loop to close the
      // rest. The socket file goes under the lock, so a later `start()` cannot lose its new file.
      Darwin.close(stopped.wakeWrite)
      unlink(socketPath)
    }
  }

  /// Ends the server when the loop stops on its own: the loop owns `wakeWrite` then, unless
  /// `stop()` already took the listener.
  private func release(_ ended: Listener) {
    stateLock.withLock {
      guard listener?.id == ended.id else { return }
      listener = nil
      Darwin.close(ended.wakeWrite)
      unlink(socketPath)
    }
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
        report(endMessage(errno))
        return
      }
      if events[1].revents != 0 { return }
      guard events[0].revents & Int16(POLLIN) != 0 else {
        report(endMessage(EIO))
        return
      }
      let connection = acceptConnection(listener.socket)
      guard connection >= 0 else {
        let goesOn = AcceptFailure.continuesAfter(
          errno: errno,
          server: Self.name,
          wake: listener.wakeRead,
          waitMilliseconds: resourceWaitMilliseconds,
          ended: .requestListenerStopped,
          report: report
        )
        if goesOn { continue }
        return
      }
      BlockingWork.detach(label: "com.openjoystickdriver.rpc.connection") { [weak self] in
        guard let self else {
          Darwin.close(connection)
          return
        }
        self.handleConnection(connection)
      }
    }
  }

  private func endMessage(_ code: Int32) -> String {
    AcceptFailure.message(
      server: Self.name,
      errno: code,
      action: .fatal,
      ended: .requestListenerStopped
    )
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
