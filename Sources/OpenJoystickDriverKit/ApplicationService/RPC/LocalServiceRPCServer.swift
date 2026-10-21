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

  /// One started server's sockets. The accept loop is the only code that closes them, so the
  /// descriptor numbers stay reserved until the loop has stopped using them and a later server
  /// cannot be handed the same numbers while this loop still polls.
  private struct Listener {
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
    // The accept loop wakes on the pipe, closes every descriptor and ends.
    var byte: UInt8 = 0
    _ = Darwin.write(stopped.wakeWrite, &byte, 1)
    unlink(socketPath)
  }

  private func acceptConnections(_ listener: Listener) {
    defer {
      Darwin.close(listener.socket)
      Darwin.close(listener.wakeRead)
      Darwin.close(listener.wakeWrite)
    }
    while true {
      var events = [
        pollfd(fd: listener.socket, events: Int16(POLLIN), revents: 0),
        pollfd(fd: listener.wakeRead, events: Int16(POLLIN), revents: 0),
      ]
      let ready = poll(&events, 2, -1)
      if ready < 0 {
        if errno == EINTR { continue }
        return
      }
      if events[1].revents != 0 { return }
      guard events[0].revents & Int16(POLLIN) != 0 else { return }
      let connection = Darwin.accept(listener.socket, nil, nil)
      guard connection >= 0 else {
        if errno == EINTR || errno == ECONNABORTED { continue }
        return
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
