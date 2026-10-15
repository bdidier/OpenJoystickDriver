import Foundation

public struct EndpointCredentials: Sendable {
  public var socketPath: String
  public var token: String
  public var tokenName: String

  public init(socketPath: String, token: String, tokenName: String) {
    self.socketPath = socketPath
    self.token = token
    self.tokenName = tokenName
  }
}

/// The bridge on the Mac that runs the game. It needs the `control` scope. A `Frame` from the
/// peer's data channel goes to the endpoint's virtual gamepad, and each `RumbleCommand` of the
/// endpoint goes back over the data channel.
public final class HostBridge: @unchecked Sendable {
  /// The endpoint closes a feed that sends no frame for 2 seconds, so the bridge repeats the last
  /// frame while the peer's controller is idle.
  static let keepAliveInterval: TimeInterval = 0.5

  private let link: PeerLink
  private let persona: String
  private let lock = NSLock()
  private var endpoint: EndpointSession?
  private var lastFrame: EndpointSession.Line = ["apiVersion": endpointAPIVersion, "kind": "Frame"]
  private var stopped = false

  /// Called when the endpoint ends the feed or the connection closes.
  public var onEnd: (@Sendable (Error?) -> Void)?

  public init(link: PeerLink, persona: String = "Generic") {
    self.link = link
    self.persona = persona
  }

  public func start(_ credentials: EndpointCredentials) throws {
    let session = try EndpointSession.connect(
      socketPath: credentials.socketPath,
      token: credentials.token,
      tokenName: credentials.tokenName,
      scopes: ["control"]
    )
    try session.send(["apiVersion": endpointAPIVersion, "kind": "FeedRequest", "as": persona])
    guard let reply = try session.readLine(), reply["kind"] as? String == "FeedSession" else {
      throw BridgeError.protocolViolation("The endpoint did not answer with a FeedSession.")
    }
    lock.lock()
    endpoint = session
    lock.unlock()
    link.onMessage = { [weak self] data in self?.receive(data) }
    Thread.detachNewThread { [weak self] in self?.readEndpoint(session) }
    Thread.detachNewThread { [weak self] in self?.keepAlive(session) }
  }

  public func stop() {
    lock.lock()
    stopped = true
    let session = endpoint
    lock.unlock()
    session?.close()
  }

  private var isStopped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }

  private func receive(_ data: Data) {
    guard let line = try? JSONSerialization.jsonObject(with: data) as? EndpointSession.Line,
      line["kind"] as? String == "Frame", line["apiVersion"] as? String == endpointAPIVersion
    else { return }
    lock.lock()
    lastFrame = line
    let session = endpoint
    lock.unlock()
    try? session?.send(line)
  }

  private func readEndpoint(_ session: EndpointSession) {
    do {
      while let line = try session.readLine() {
        guard line["kind"] as? String == "RumbleCommand",
          let data = try? JSONSerialization.data(withJSONObject: line)
        else { continue }
        link.send(data)
      }
      finish(nil)
    } catch { finish(error) }
  }

  private func keepAlive(_ session: EndpointSession) {
    while !isStopped {
      Thread.sleep(forTimeInterval: Self.keepAliveInterval)
      lock.lock()
      let frame = lastFrame
      lock.unlock()
      if (try? session.send(frame)) == nil { return }
    }
  }

  private func finish(_ error: Error?) {
    if isStopped { return }
    onEnd?(error)
  }
}

/// The bridge on the player's Mac. It needs the `read` scope. It subscribes to the controllers,
/// sends the chosen controller's input as `Frame` lines over the data channel, and reports each
/// `RumbleCommand` that the peer sends back. The endpoint has no message that drives a physical
/// controller's rumble, so the bridge only reports the commands.
public final class PlayerBridge: @unchecked Sendable {
  private let link: PeerLink
  private let controller: String?
  private let lock = NSLock()
  private var endpoint: EndpointSession?
  private var chosen: String?
  private var stopped = false

  public var onRumble: (@Sendable (EndpointSession.Line) -> Void)?
  public var onEnd: (@Sendable (Error?) -> Void)?

  /// `controller` is the `id` from the watch lines; without it, the first controller that the
  /// endpoint reports.
  public init(link: PeerLink, controller: String? = nil) {
    self.link = link
    self.controller = controller
    self.chosen = controller
  }

  public func start(_ credentials: EndpointCredentials) throws {
    let session = try EndpointSession.connect(
      socketPath: credentials.socketPath,
      token: credentials.token,
      tokenName: credentials.tokenName,
      scopes: ["read"]
    )
    try session.send([
      "apiVersion": endpointAPIVersion, "kind": "Subscription", "stream": "controllers",
    ])
    lock.lock()
    endpoint = session
    lock.unlock()
    link.onMessage = { [weak self] data in
      guard let line = try? JSONSerialization.jsonObject(with: data) as? EndpointSession.Line,
        line["kind"] as? String == "RumbleCommand"
      else { return }
      self?.onRumble?(line)
    }
    Thread.detachNewThread { [weak self] in self?.readEndpoint(session) }
  }

  public func stop() {
    lock.lock()
    stopped = true
    let session = endpoint
    lock.unlock()
    session?.close()
  }

  private func readEndpoint(_ session: EndpointSession) {
    do {
      while let line = try session.readLine() {
        forward(line)
      }
      finish(nil)
    } catch { finish(error) }
  }

  private func forward(_ line: EndpointSession.Line) {
    if chosen == nil, line["type"] as? String == "ADDED",
      let object = line["object"] as? [String: Any], let id = object["id"] as? String
    {
      chosen = id
    }
    guard let (id, frame) = FrameTranslation.frame(fromWatchLine: line), id == chosen,
      let data = try? JSONSerialization.data(withJSONObject: frame)
    else { return }
    link.send(data)
  }

  private func finish(_ error: Error?) {
    lock.lock()
    let wasStopped = stopped
    lock.unlock()
    if !wasStopped { onEnd?(error) }
  }
}
