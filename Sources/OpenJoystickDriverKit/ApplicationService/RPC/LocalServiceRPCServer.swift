import Darwin
import Foundation

public final class LocalServiceRPCServer: @unchecked Sendable {
  public typealias Authentication = @Sendable (LocalSocketPeer) -> Bool
  public typealias Completion = @Sendable (LocalServiceRPCResponse) -> Void
  public typealias Handler = @Sendable (LocalServiceRPCRequest, @escaping Completion) -> Void

  /// Answers a request and is cancelled when the client closes its end first.
  package typealias CancellableHandler =
    @Sendable (LocalServiceRPCRequest) async -> LocalServiceRPCResponse

  /// How a request is answered.
  private enum Dispatch {
    /// The handler completes on its own schedule and is never told that the client left.
    case callback(Handler)
    /// The server runs the handler in a task and cancels the task when the client hangs up
    /// before the response, so a held request does not outlive its client.
    case cancellable(CancellableHandler)
  }

  /// How often a pending cancellable request checks whether its handler finished.
  private static let pendingPollMilliseconds: Int32 = 50

  private let authentication: Authentication
  private let dispatch: Dispatch
  package let socketPath: String
  private let stateLock = NSLock()
  private var listener: Listener?
  /// True while a `start()` call sets up the sockets, so a second call is refused.
  private var starting = false
  /// True when `stop()` ran while `starting`; `start()` stops the server it finished.
  private var stopRequested = false

  /// Told after every change of the listener's failure: the failure when the accept loop ends
  /// on a fatal error, nil when a start clears it. The service sets it before `start()`.
  package var listenerFailureChanged: (@Sendable (ServiceListenerFailure?) -> Void)?

  // The five hooks below belong to tests; set them before `start()`.
  /// Runs inside `start()` after the sockets are listening and before the server publishes them.
  package var beforeListenerPublished: (@Sendable () -> Void)?
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
  /// The process that runs the server, written into every listener failure record.
  private let process = ServiceListenerFailure.ProcessIdentity.current

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
    self.dispatch = .callback(handler)
  }

  /// A server whose handler is cancelled when the client closes its connection before the
  /// response. A client sends one request and then only reads, so any event on the connection
  /// while the handler runs, a hang-up, an error or stray bytes, ends the request.
  package init(
    socketPath: String = LocalServiceRPCTransport.defaultSocketPath,
    authentication: @escaping Authentication,
    cancellableHandler: @escaping CancellableHandler
  ) {
    self.socketPath = socketPath
    self.authentication = authentication
    self.dispatch = .cancellable(cancellableHandler)
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
      beforeListenerPublished?()
      stateLock.withLock {
        listener = started
        starting = false
        clearListenerFailure()
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

  /// Stops the server and deletes the record of a listener failure, also when the listener
  /// already stopped on its own: an orderly stop leaves nothing for `ojd` to report. A call while
  /// `start()` still sets up the sockets takes effect as soon as that call returns.
  public func stop() {
    stateLock.withLock {
      deleteListenerFailureRecord()
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
  /// Returns whether the loop ended the server, as opposed to `stop()` having done so. A fatal
  /// `failure` is recorded under the same lock, so a start that follows clears the record after it
  /// was written and a late write never replaces that clear.
  private func release(_ ended: Listener, failure: Int32?) -> Bool {
    stateLock.withLock {
      guard listener?.id == ended.id else { return false }
      listener = nil
      Darwin.close(ended.wakeWrite)
      unlink(socketPath)
      if let failure { recordListenerFailure(errno: failure) }
      return true
    }
  }

  /// Runs the loop. A loop that ends on a fatal error records why in a file beside the socket and
  /// in `listenerFailureChanged`, because the RPC socket cannot carry the reason once it is gone.
  /// The process keeps running.
  private func acceptConnections(_ listener: Listener) {
    let failure = acceptUntilEnd(listener)
    _ = release(listener, failure: failure)
    Darwin.close(listener.socket)
    Darwin.close(listener.wakeRead)
    acceptLoopDidExit?()
  }

  /// Accepts connections until the server stops, and returns the error number of a fatal error.
  private func acceptUntilEnd(_ listener: Listener) -> Int32? {
    while true {
      var events = [
        pollfd(fd: listener.socket, events: Int16(POLLIN), revents: 0),
        pollfd(fd: listener.wakeRead, events: Int16(POLLIN), revents: 0),
      ]
      let ready = poll(&events, 2, -1)
      if ready < 0 {
        let code = errno
        if code == EINTR { continue }
        report(endMessage(code))
        return code
      }
      if events[1].revents != 0 { return nil }
      guard events[0].revents & Int16(POLLIN) != 0 else {
        report(endMessage(EIO))
        return EIO
      }
      let connection = acceptConnection(listener.socket)
      guard connection >= 0 else {
        let next = AcceptFailure.continuation(
          errno: errno,
          server: Self.name,
          wake: listener.wakeRead,
          waitMilliseconds: resourceWaitMilliseconds,
          ended: .requestListenerStopped,
          report: report
        )
        switch next {
        case .goOn: continue
        case .stopped: return nil
        case .ended(let code): return code
        }
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

  private func recordListenerFailure(errno code: Int32) {
    let failure = ServiceListenerFailure(
      errorNumber: code,
      time: Date(),
      process: process
    )
    defer { listenerFailureChanged?(failure) }
    do { try failure.write(socketPath: socketPath) } catch {
      report(
        "[\(Self.name)] Could not record why the request listener stopped in "
          + "\(ServiceListenerFailure.path(forSocket: socketPath)): \(error.localizedDescription)"
      )
    }
  }

  /// A listener that starts deletes the record of the last failure. Runs under `stateLock`.
  private func clearListenerFailure() {
    deleteListenerFailureRecord()
    listenerFailureChanged?(nil)
  }

  private func deleteListenerFailureRecord() {
    do { try ServiceListenerFailure.clear(socketPath: socketPath) } catch {
      report(
        "[\(Self.name)] Could not delete the record of the last listener failure: "
          + error.localizedDescription
      )
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
      switch dispatch {
      case .callback(let handler):
        handler(request) { response in
          defer { Darwin.close(descriptor) }
          guard let encoded = try? JSONEncoder().encode(response) else { return }
          try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
        }
      case .cancellable(let handler):
        answer(request, on: descriptor, with: handler)
      }
    } catch {
      let response = LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
      if let encoded = try? JSONEncoder().encode(response) {
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
      Darwin.close(descriptor)
    }
  }

  /// Runs `handler` for `request` and sends its response, cancelling it if the client leaves
  /// first. Returns after the connection is closed.
  private func answer(
    _ request: LocalServiceRPCRequest,
    on descriptor: Int32,
    with handler: @escaping CancellableHandler
  ) {
    let finished = DispatchSemaphore(value: 0)
    let done = Locked(false)
    let task = Task {
      let response = await handler(request)
      if let encoded = try? JSONEncoder().encode(response) {
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
      done.withLock { $0 = true }
      finished.signal()
    }
    var events = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    while !done.withLock({ $0 }) {
      let ready = poll(&events, 1, Self.pendingPollMilliseconds)
      if ready > 0 || (ready < 0 && errno != EINTR) {
        task.cancel()
        break
      }
    }
    finished.wait()
    Darwin.close(descriptor)
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
