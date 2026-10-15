import XCTest

@testable import WebRTCBridgeCore

final class BridgeTests: XCTestCase {
  func testProofMatchesTheDocumentedConstruction() {
    // Same construction as Scripts/SDK/reference_client.py: HMAC-SHA256 over four lines.
    let proof = EndpointSession.proof(token: "ojd_x", nonce: "abc")
    XCTAssertEqual(proof.count, 64)
    XCTAssertEqual(proof, EndpointSession.proof(token: "ojd_x", nonce: "abc"))
    XCTAssertNotEqual(proof, EndpointSession.proof(token: "ojd_x", nonce: "abd"))
  }

  func testAWatchLineBecomesAFrame() throws {
    let line = Self.modified(pressed: ["face-south", "unknown-control"], hat: "northEast")
    let (id, frame) = try XCTUnwrap(FrameTranslation.frame(fromWatchLine: line))
    XCTAssertEqual(id, "pad-1")
    XCTAssertEqual(frame["kind"] as? String, "Frame")
    XCTAssertEqual(frame["buttons"] as? [String], ["south"])
    XCTAssertEqual(frame["dpad"] as? [String], ["up", "right"])
    let axes = try XCTUnwrap(frame["axes"] as? [String: Double])
    XCTAssertEqual(axes["left_stick_y"], 1)
    XCTAssertEqual(axes["right_trigger"], 1)
    XCTAssertNil(FrameTranslation.frame(fromWatchLine: ["type": "ADDED", "object": [:]]))
  }

  func testAWrongTokenIsRefused() throws {
    let endpoint = try FakeEndpoint()
    endpoint.serve(connections: 1)
    XCTAssertThrowsError(
      try EndpointSession.connect(
        socketPath: endpoint.path,
        token: "wrong",
        tokenName: FakeEndpoint.tokenName,
        scopes: ["read"]
      )
    ) { error in
      XCTAssertEqual((error as? BridgeError)?.description.hasPrefix("E1002"), true)
    }
  }

  /// Two bridges in one process, joined by a real data channel: a controller frame goes from the
  /// player to the host's virtual gamepad, and the rumble command goes back.
  func testLoopbackPassesAFrameOneWayAndRumbleBack() async throws {
    let rumble: [String: Any] = [
      "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": "setRumble",
      "intensities": ["leftMain": 65535], "durationMilliseconds": 200,
    ]
    let hostEndpoint = try FakeEndpoint(rumble: rumble)
    let playerEndpoint = try FakeEndpoint(watchLines: [
      [
        "type": "ADDED",
        "object": ["apiVersion": endpointAPIVersion, "kind": "Controller", "id": "pad-1"],
      ],
      Self.modified(pressed: ["face-south"], hat: "neutral"),
    ])
    hostEndpoint.serve(connections: 1)
    playerEndpoint.serve(connections: 1)

    let player = try PeerLink(role: .offer)
    let host = try PeerLink(role: .answer)
    let offer = try await player.localBlob()
    try await host.accept(offer)
    let answer = try await host.localBlob()
    try await player.accept(answer)
    await player.waitUntilOpen()
    await host.waitUntilOpen()

    let received = expectation(description: "the player receives the rumble command")
    let hostBridge = HostBridge(link: host)
    let playerBridge = PlayerBridge(link: player)
    nonisolated(unsafe) var rumbleLine: [String: Any]?
    playerBridge.onRumble = { line in
      rumbleLine = line
      received.fulfill()
    }
    try hostBridge.start(
      EndpointCredentials(
        socketPath: hostEndpoint.path,
        token: FakeEndpoint.token,
        tokenName: FakeEndpoint.tokenName
      )
    )
    try playerBridge.start(
      EndpointCredentials(
        socketPath: playerEndpoint.path,
        token: FakeEndpoint.token,
        tokenName: FakeEndpoint.tokenName
      )
    )

    await fulfillment(of: [received], timeout: 20)
    XCTAssertEqual(rumbleLine?["type"] as? String, "setRumble")
    XCTAssertEqual((rumbleLine?["intensities"] as? [String: Int])?["leftMain"], 65535)

    let host1 = hostEndpoint.snapshot()
    XCTAssertEqual(host1.requests.first?["kind"] as? String, "FeedRequest")
    XCTAssertEqual(host1.proofs, [true])
    XCTAssertTrue(host1.frames.contains { ($0["buttons"] as? [String]) == ["south"] })
    let player1 = playerEndpoint.snapshot()
    XCTAssertEqual(player1.requests.first?["kind"] as? String, "Subscription")
    XCTAssertEqual(player1.proofs, [true])

    // Both fake endpoints closed their listening sockets after one accept; the bridges and the
    // WebRTC stack must not hold any listening socket.
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(ListeningSockets.ofThisProcess(), [])

    hostBridge.stop()
    playerBridge.stop()
    host.close()
    player.close()
  }

  func testTheScanSeesAListeningSocket() throws {
    let endpoint = try FakeEndpoint()
    XCTAssertEqual(ListeningSockets.ofThisProcess().count, 1)
    endpoint.serve(connections: 0)
  }

  private static func modified(pressed: [String], hat: String) -> [String: Any] {
    [
      "type": "MODIFIED",
      "object": [
        "apiVersion": endpointAPIVersion, "kind": "Controller", "id": "pad-1",
        "input": [
          "pressed": pressed, "hat": hat, "leftStick": ["x": 0, "y": 32767],
          "rightStick": ["x": 0, "y": 0], "leftTrigger": 0, "rightTrigger": 65535, "touch": [],
        ],
      ],
    ]
  }
}
