import Darwin
import Foundation
import OpenJoystickDriverKit

/// The opt-in socket on which granted local programs read controller events, and the opt-in
/// WebSocket on `127.0.0.1` for token clients such as browser overlays.
///
/// `AccessGrants.json` says whether each listens and which signed clients and tokens it serves;
/// the socket exists only while the endpoint is enabled.
///
/// - Note: `@unchecked Sendable` because the mutable fields are guarded by `lock`. Grant and
///   revoke changes and the handshake's grant check hold it too, so a client cannot be welcomed
///   with a grant that a concurrent revoke already removed.
final class EndpointServer: @unchecked Sendable {
  typealias Identify = @Sendable (LocalSocketPeer) -> EndpointClient?

  /// The most connections each transport serves, so web pages cannot starve socket clients.
  static let maximumConnections = 8
  static let maximumLineBytes = 65_536
  static let handshakeSeconds = 5
  static let maximumQueuedLines = 256
  /// Web connections that have not upgraded or finished their page request yet.
  static let maximumPendingWebRequests = 16
  static let maximumRequestBytes = 8_192
  static let socketName = "com.openjoystickdriver.endpoint.sock"

  /// The socket in the per-user temporary folder, which only the user can open.
  static var defaultSocketPath: String {
    MacOSDataDirectory().fileURL(socketName, in: .runtime).path
  }

  let socketPath: String
  let store: AccessGrantStore
  let source: any ControllerWatchSource
  let version: String
  /// The virtual gamepads that `feed` connections drive; shared with `ojd virtual feed`. Nil
  /// refuses every feed.
  let feeds: VirtualFeedRegistry?
  let identify: Identify
  /// Told when a stream line about a controller went to the subscribers, with the uptime in
  /// nanoseconds just after the send.
  let streamDelivered: (@Sendable (ControllerSessionToken, UInt64) async -> Void)?
  let lock = NSLock()
  private var listener: AcceptListener?
  /// Changes each time the socket starts or stops listening; ends the earlier listener's loop.
  private var socketGeneration = 0
  private var runningSocketAcceptLoops = 0
  var webListener: AcceptListener?
  /// Changes each time the WebSocket starts or stops listening; ends the earlier listener's loop.
  var webGeneration = 0
  var pendingWebRequests = 0
  /// Every accepted connection, including those still in the handshake.
  var connections: [ObjectIdentifier: EndpointConnection] = [:]
  /// The number of accepted connections that have not finished, including those in the handshake.
  var connectionCount: Int { lock.withLock { connections.count } }
  /// The number of socket accept loops that have not returned, including stale ones that a
  /// stopped listener is still waking.
  var socketAcceptLoopCount: Int { lock.withLock { runningSocketAcceptLoops } }
  var runningWebAcceptLoops = 0
  /// The number of WebSocket accept loops that have not returned, including stale ones that a
  /// stopped listener is still waking.
  var webAcceptLoopCount: Int { lock.withLock { runningWebAcceptLoops } }
  /// Called by each accept loop after its generation check and before it waits for a connection;
  /// tests hold a loop there to let the listener change under it.
  let beforeAcceptWait: (@Sendable (AccessTransport, Int) -> Void)?
  var refusals = AccessRefusalLog()
  var stream = EndpointStream()

  init(
    socketPath: String = EndpointServer.defaultSocketPath,
    store: AccessGrantStore = AccessGrantStore(),
    source: any ControllerWatchSource,
    version: String = ApplicationVersion.current,
    feeds: VirtualFeedRegistry? = nil,
    identify: @escaping Identify = EndpointClient.identify,
    streamDelivered: (@Sendable (ControllerSessionToken, UInt64) async -> Void)? = nil,
    beforeAcceptWait: (@Sendable (AccessTransport, Int) -> Void)? = nil
  ) {
    self.beforeAcceptWait = beforeAcceptWait
    self.socketPath = socketPath
    self.store = store
    self.source = source
    self.version = version
    self.feeds = feeds
    self.streamDelivered = streamDelivered
    self.identify = identify
  }

  /// Listens when the endpoint or its WebSocket is enabled; a damaged grants file keeps both
  /// closed.
  func start() {
    let file: AccessGrantFile
    do { file = try store.load() } catch {
      print("[EndpointServer] Not listening: \(error.localizedDescription)")
      return
    }
    // Each listener starts on its own, so a socket that fails does not keep the WebSocket off.
    do { if file.enabled { try lock.withLock { try listen() } } } catch {
      print("[EndpointServer] Socket not listening: \(error.localizedDescription)")
    }
    do {
      if file.web.enabled, let port = file.web.port {
        try lock.withLock { startWebListening(try openWebListener(port: port)) }
      }
    } catch {
      print("[EndpointServer] WebSocket not listening: \(error.localizedDescription)")
    }
  }

  /// Stops listening and closes every connection; the grants file is left as it is.
  func stop() {
    lock.withLock {
      stopListening()
      stopWebListening()
      stream.stop()
      for connection in connections.values { connection.close(nil) }
    }
  }

  func status() throws -> AccessStatusPayload {
    try lock.withLock {
      let file = try store.load()
      return AccessStatusPayload(
        enabled: file.enabled,
        socketPath: socketPath,
        connections: connections.values.filter { !$0.isClosing }.compactMap(\.session)
          .sorted { ($0.identifier, $0.id) < ($1.identifier, $1.id) },
        grants: file.grants.map(AccessGrantSummary.init),
        refused: refusals.clients(at: Date()),
        web: AccessWebStatus(
          enabled: file.web.enabled,
          listening: webListener != nil,
          port: webListener?.port ?? file.web.port,
          pagesPath: store.pagesDirectory.path
        ),
        tokens: file.tokens.map(\.summary),
        refusedTokens: refusals.tokens(at: Date())
      )
    }
  }

  /// Saves the flag and opens or removes the socket; disabling closes every socket connection
  /// with `E1001`.
  func setEnabled(_ enabled: Bool) throws {
    try lock.withLock {
      var file = try store.load()
      file.enabled = enabled
      if enabled {
        let wasListening = listener != nil
        if !wasListening { try listen() }
        do { try store.save(file) } catch {
          if !wasListening { stopListening() }
          throw error
        }
      } else {
        try store.save(file)
        stopListening()
        let error = EndpointError(code: .endpointDisabled, message: "The endpoint was disabled.")
        for connection in connections.values where connection.kind == .socket {
          connection.close(error)
        }
      }
    }
  }

  @discardableResult
  func grant(
    _ identity: CodeSigningIdentity,
    path: String,
    scopes: [EndpointScope]
  ) throws -> AccessGrantSummary {
    guard identity.requirement != nil else {
      throw AccessGrantStoreError.notGrantable(identity.kind)
    }
    guard !scopes.isEmpty else { throw AccessGrantStoreError.noScope }
    return try lock.withLock {
      var file = try store.load()
      let grant = file.grant(identity, scopes: scopes, path: path, at: Date())
      try store.save(file)
      refusals.remove(id: identity.accessID)
      return AccessGrantSummary(grant)
    }
  }

  /// Adds a token grant; the token is returned only here.
  @discardableResult
  func grantToken(
    name: String,
    origins: [String],
    scopes: [EndpointScope]
  ) throws -> AccessTokenGrantResult {
    try lock.withLock {
      var file = try store.load()
      let (token, grant) = try file.grantToken(
        name: name,
        origins: origins,
        scopes: scopes,
        at: Date()
      )
      try store.save(file)
      return AccessTokenGrantResult(token: token, grant: grant.summary)
    }
  }

  /// Removes `scopes`, or the whole grant when nil, from a client or a `token:NAME` grant, and
  /// closes with `E1005` every connection that holds a scope no longer granted.
  func revoke(id: String, scopes: [EndpointScope]?) throws -> AccessRevokeResult {
    try lock.withLock {
      var file = try store.load()
      let remainingScopes: [EndpointScope]
      var result: (grant: AccessGrantSummary?, token: AccessTokenSummary?)
      if id.hasPrefix("token:") {
        let remaining = try file.revokeToken(id: id, scopes: scopes)
        remainingScopes = remaining?.scopes ?? []
        result.token = remaining?.summary
      } else {
        let remaining = try file.revoke(id: id, scopes: scopes)
        remainingScopes = remaining?.scopes ?? []
        result.grant = remaining.map(AccessGrantSummary.init)
      }
      try store.save(file)
      var closed = 0
      for connection in connections.values {
        guard let session = connection.session, session.id == id,
          !session.scopes.allSatisfy(remainingScopes.contains)
        else { continue }
        connection.close(EndpointError(code: .revoked, message: "The client's grant was revoked."))
        closed += 1
      }
      return AccessRevokeResult(
        id: id,
        grant: result.grant,
        token: result.token,
        closedConnections: closed
      )
    }
  }

  // MARK: - Socket

  /// Call with `lock` held.
  private func listen() throws {
    guard listener == nil else { return }
    try removeStaleSocket()
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    do {
      var address = try LocalServiceRPCTransport.socketAddress(path: socketPath)
      let bindStatus = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(
            descriptor,
            $0,
            LocalServiceRPCTransport.socketAddressLength(path: socketPath)
          )
        }
      }
      guard bindStatus == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      guard chmod(socketPath, S_IRUSR | S_IWUSR) == 0, Darwin.listen(descriptor, 16) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
    } catch {
      Darwin.close(descriptor)
      unlink(socketPath)
      throw error
    }
    let socketListener: AcceptListener
    do { socketListener = try AcceptListener(listening: descriptor) } catch {
      unlink(socketPath)
      throw error
    }
    listener = socketListener
    socketGeneration += 1
    let generation = socketGeneration
    runningSocketAcceptLoops += 1
    // The accept loops and the handshake timers run on threads of their own (`detachThread`),
    // never on a constrained pool thread of Grand Central Dispatch: those threads are limited,
    // and a saturated pool would delay accepts and handshake timeouts. Each connection runs on a
    // serial queue of its own (`detach`), which starts at once even when the pool is saturated.
    // A stale web listener's loop, which may stay blocked, holds only its own thread and never
    // holds up a later one.
    BlockingWork.detachThread(name: "com.openjoystickdriver.endpoint.accept") { [weak self] in
      guard let self else {
        socketListener.finish()
        return
      }
      self.acceptConnections(socketListener, generation: generation)
    }
  }

  /// Call with `lock` held.
  private func stopListening() {
    guard let stopped = listener else { return }
    // `wake` frees the address at once; the loop closes the descriptor when it wakes, so the
    // number stays taken until then.
    stopped.wake()
    listener = nil
    socketGeneration += 1
    unlink(socketPath)
  }

  /// Removes a socket file that a stopped service left behind; refuses any other file.
  private func removeStaleSocket() throws {
    var information = stat()
    guard lstat(socketPath, &information) == 0 else { return }
    guard information.st_uid == geteuid(), information.st_mode & S_IFMT == S_IFSOCK else {
      throw LocalServiceRPCError.peerRejected
    }
    guard unlink(socketPath) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
  }

  /// Owns the listener: waits on it and on its wake pipe, and closes it when it ends. The
  /// descriptor stays open until then, so its number cannot belong to a later listener. A
  /// connection accepted after the listener was replaced is dropped.
  private func acceptConnections(_ listener: AcceptListener, generation: Int) {
    defer {
      listener.finish()
      lock.withLock { runningSocketAcceptLoops -= 1 }
    }
    while lock.withLock({ socketGeneration == generation }) {
      beforeAcceptWait?(.socket, generation)
      switch listener.wait() {
      case .woken: return
      case .failed(let code):
        print("[EndpointServer] Socket accept loop ends: poll failed with errno \(code)")
        return
      case .ready: break
      }
      guard let accepted = listener.accept() else {
        // EAGAIN: the pending connection was dropped between poll and accept; wait again.
        // Running out of descriptors or memory is retried after a pause.
        guard Self.pause(after: Self.acceptFailure(errno)) else { return }
        continue
      }
      guard lock.withLock({ socketGeneration == generation }) else {
        Darwin.close(accepted)
        return
      }
      var noSignal: Int32 = 1
      setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
      BlockingWork.detach(label: "com.openjoystickdriver.endpoint.connection") { [weak self] in
        guard let self else {
          Darwin.close(accepted)
          return
        }
        self.serve(EndpointConnection(descriptor: accepted))
      }
    }
  }

  // MARK: - Accept failures

  enum AcceptFailure: Equatable {
    /// An interrupted or aborted accept, or none waiting; wait again at once.
    case retry
    /// The process or system is out of descriptors or memory; accept again after a pause.
    case backOff
    /// The listener is closed or broken.
    case stop
  }

  static let acceptBackOffMicroseconds: useconds_t = 100_000

  static func acceptFailure(_ code: Int32) -> AcceptFailure {
    switch code {
    case EINTR, ECONNABORTED, EAGAIN: .retry
    case EMFILE, ENFILE, ENOBUFS, ENOMEM: .backOff
    default: .stop
    }
  }

  /// Waits out a back-off; false when the loop should end.
  static func pause(after failure: AcceptFailure) -> Bool {
    switch failure {
    case .retry: return true
    case .backOff:
      usleep(acceptBackOffMicroseconds)
      return true
    case .stop: return false
    }
  }
}
