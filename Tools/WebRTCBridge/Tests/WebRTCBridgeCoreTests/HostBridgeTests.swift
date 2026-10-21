import XCTest

@testable import BridgeCore
@testable import WebRTCBridgeCore

/// A data channel in memory: the test plays the peer.
private final class FakeChannel: PeerChannel, @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (Data) -> Void)?
  private var messages: [Data] = []

  var onMessage: (@Sendable (Data) -> Void)? {
    get { lock.withLock { handler } }
    set { lock.withLock { handler = newValue } }
  }

  var sent: [Data] { lock.withLock { messages } }

  func send(_ data: Data) -> Bool {
    lock.withLock { messages.append(data) }
    return true
  }

  func peerSends(_ text: String) { onMessage?(Data(text.utf8)) }
}

final class HostBridgeTests: XCTestCase {
  private static let header = #""apiVersion":"openjoystickdriver/v1alpha1""#

  private func started(
    _ endpoint: FakeEndpoint
  ) throws -> (bridge: HostBridge, channel: FakeChannel) {
    endpoint.serve(connections: 1)
    let channel = FakeChannel()
    let bridge = HostBridge(link: channel)
    try bridge.start(
      EndpointCredentials(
        socketPath: endpoint.path,
        token: FakeEndpoint.token,
        tokenName: FakeEndpoint.tokenName
      )
    )
    return (bridge, channel)
  }

  func testAnInvalidPeerMessageProducesNoEndpointWrite() async throws {
    let endpoint = try FakeEndpoint()
    let (bridge, channel) = try started(endpoint)
    channel.peerSends("not json")
    channel.peerSends(#"{\#(Self.header),"kind":"Frame","holdMilliseconds":60001}"#)
    channel.peerSends(#"{\#(Self.header),"kind":"Frame","extra":true}"#)
    channel.peerSends(#"{\#(Self.header),"kind":"KeepAlive"}"#)
    try await Task.sleep(nanoseconds: 300_000_000)

    XCTAssertEqual(endpoint.snapshot().frames.count, 0)
    bridge.stop()
  }

  func testAFrameIsSentOnceAndAnIdleFeedGetsOnlyKeepAlive() async throws {
    let endpoint = try FakeEndpoint()
    let (bridge, channel) = try started(endpoint)
    channel.peerSends(#"{\#(Self.header),"kind":"Frame","buttons":["South"]}"#)
    try await Task.sleep(nanoseconds: 1_700_000_000)

    let frames = endpoint.snapshot().frames
    XCTAssertEqual(frames.count, 1)
    XCTAssertEqual(frames.first?["buttons"] as? [String], ["South"])
    XCTAssertGreaterThanOrEqual(endpoint.keepAliveCount(), 2)
    bridge.stop()
  }

  func testOnlyAValidRumbleCommandOfTheEndpointGoesToThePeer() async throws {
    let rumble: [String: Any] = [
      "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": "StopRumble",
    ]
    let oversize: [String: Any] = [
      "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": "StopRumble",
      "padding": String(repeating: "x", count: PeerMessage.maximumBytes),
    ]
    let endpoint = try FakeEndpoint(
      rumble: rumble,
      feedLines: [
        ["apiVersion": endpointAPIVersion, "kind": "Status", "status": "Success"],
        ["apiVersion": endpointAPIVersion, "kind": "Frame"],
        oversize,
      ]
    )
    let (bridge, channel) = try started(endpoint)
    channel.peerSends(#"{\#(Self.header),"kind":"Frame","buttons":["South"]}"#)
    try await Task.sleep(nanoseconds: 500_000_000)

    let sent = channel.sent.compactMap {
      try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    }
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(sent.first?["kind"] as? String, "RumbleCommand")
    XCTAssertEqual(sent.first?["type"] as? String, "StopRumble")
    bridge.stop()
  }
}
