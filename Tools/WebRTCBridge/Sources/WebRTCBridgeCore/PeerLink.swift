import Foundation
import LiveKitWebRTC

/// Which side creates the offer. The offerer also opens the data channel.
public enum SignalingRole: String, Sendable {
  case offer
  case answer
}

/// One WebRTC data channel to one peer.
///
/// The offer and the answer travel out of band as a blob: base64 of a JSON object with `type` and
/// `sdp`. The blob is made after ICE gathering has finished, so the SDP carries the candidates and
/// no trickle exchange is needed. The link opens no listening socket: ICE binds UDP sockets for
/// the data channel, and TCP candidates are off.
public final class PeerLink: NSObject, @unchecked Sendable {
  public static let channelLabel = "ojd"

  /// Called on a WebRTC thread with each message of the data channel.
  public var onMessage: (@Sendable (Data) -> Void)?
  public var onOpen: (@Sendable () -> Void)?

  private static let factory = LKRTCPeerConnectionFactory()

  private let role: SignalingRole
  private let lock = NSLock()
  private var connection: LKRTCPeerConnection!
  private var channel: LKRTCDataChannel?
  private var gatheringWaiters: [CheckedContinuation<Void, Never>] = []
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  public init(role: SignalingRole, iceServers: [String] = []) throws {
    self.role = role
    super.init()
    let configuration = LKRTCConfiguration()
    configuration.sdpSemantics = .unifiedPlan
    configuration.tcpCandidatePolicy = .disabled
    configuration.iceServers = iceServers.isEmpty ? [] : [LKRTCIceServer(urlStrings: iceServers)]
    let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard
      let connection = Self.factory.peerConnection(
        with: configuration,
        constraints: constraints,
        delegate: self
      )
    else { throw BridgeError.signaling("WebRTC could not create a peer connection.") }
    self.connection = connection
    if role == .offer {
      let settings = LKRTCDataChannelConfiguration()
      settings.isOrdered = true
      guard
        let channel = connection.dataChannel(
          forLabel: Self.channelLabel,
          configuration: settings
        )
      else { throw BridgeError.signaling("WebRTC could not create the data channel.") }
      attach(channel)
    }
  }

  /// For the offerer: the offer blob. For the answerer: call ``accept(_:)`` first, then this.
  public func localBlob() async throws -> String {
    let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    let description: LKRTCSessionDescription =
      try await withCheckedThrowingContinuation { continuation in
        let completion: @Sendable (LKRTCSessionDescription?, Error?) -> Void = { sdp, error in
          if let sdp {
            continuation.resume(returning: sdp)
          } else {
            continuation.resume(throwing: error ?? BridgeError.signaling("No description."))
          }
        }
        if role == .offer {
          connection.offer(for: constraints, completionHandler: completion)
        } else {
          connection.answer(for: constraints, completionHandler: completion)
        }
      }
    try await setLocal(description)
    await waitForGathering()
    guard let local = connection.localDescription else {
      throw BridgeError.signaling("The peer connection has no local description.")
    }
    return try Self.encode(local)
  }

  /// Applies the peer's blob: the answer for the offerer, the offer for the answerer.
  public func accept(_ blob: String) async throws {
    let description = try Self.decode(blob)
    let expected: LKRTCSdpType = role == .offer ? .answer : .offer
    guard description.type == expected else {
      throw BridgeError.signaling("Expected an \(role == .offer ? "answer" : "offer") blob.")
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.setRemoteDescription(description) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  public func waitUntilOpen() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if channel?.readyState == .open {
        lock.unlock()
        continuation.resume()
      } else {
        openWaiters.append(continuation)
        lock.unlock()
      }
    }
  }

  @discardableResult
  public func send(_ data: Data) -> Bool {
    lock.lock()
    let channel = channel
    lock.unlock()
    return channel?.sendData(LKRTCDataBuffer(data: data, isBinary: false)) ?? false
  }

  public func close() {
    channel?.close()
    connection.close()
  }

  private func setLocal(_ description: LKRTCSessionDescription) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.setLocalDescription(description) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  private func waitForGathering() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if connection.iceGatheringState == .complete {
        lock.unlock()
        continuation.resume()
      } else {
        gatheringWaiters.append(continuation)
        lock.unlock()
      }
    }
  }

  private func attach(_ channel: LKRTCDataChannel) {
    lock.lock()
    self.channel = channel
    lock.unlock()
    channel.delegate = self
  }

  private static func encode(_ description: LKRTCSessionDescription) throws -> String {
    let object = [
      "type": LKRTCSessionDescription.string(for: description.type), "sdp": description.sdp,
    ]
    return try JSONSerialization.data(withJSONObject: object).base64EncodedString()
  }

  static func decode(_ blob: String) throws -> LKRTCSessionDescription {
    guard blob.utf8.count <= PeerMessage.maximumBytes else {
      throw BridgeError.signaling("The blob is longer than \(PeerMessage.maximumBytes) bytes.")
    }
    guard let data = Data(base64Encoded: blob.trimmingCharacters(in: .whitespacesAndNewlines)),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let type = object["type"], let sdp = object["sdp"]
    else { throw BridgeError.signaling("The blob is not a session description.") }
    return LKRTCSessionDescription(type: LKRTCSessionDescription.type(for: type), sdp: sdp)
  }
}

extension PeerLink: LKRTCPeerConnectionDelegate {
  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didChange stateChanged: LKRTCSignalingState
  ) {}
  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didAdd stream: LKRTCMediaStream
  ) {}
  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didRemove stream: LKRTCMediaStream
  ) {}
  public func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didChange newState: LKRTCIceConnectionState
  ) {}
  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didGenerate candidate: LKRTCIceCandidate
  ) {}
  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didRemove candidates: [LKRTCIceCandidate]
  ) {}

  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didChange newState: LKRTCIceGatheringState
  ) {
    guard newState == .complete else { return }
    lock.lock()
    let waiters = gatheringWaiters
    gatheringWaiters = []
    lock.unlock()
    waiters.forEach { $0.resume() }
  }

  public func peerConnection(
    _ peerConnection: LKRTCPeerConnection,
    didOpen dataChannel: LKRTCDataChannel
  ) {
    attach(dataChannel)
    if dataChannel.readyState == .open { opened() }
  }
}

extension PeerLink: LKRTCDataChannelDelegate {
  public func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
    if dataChannel.readyState == .open { opened() }
  }

  public func dataChannel(
    _ dataChannel: LKRTCDataChannel,
    didReceiveMessageWith buffer: LKRTCDataBuffer
  ) {
    onMessage?(buffer.data)
  }

  private func opened() {
    lock.lock()
    let waiters = openWaiters
    openWaiters = []
    lock.unlock()
    waiters.forEach { $0.resume() }
    onOpen?()
  }
}
