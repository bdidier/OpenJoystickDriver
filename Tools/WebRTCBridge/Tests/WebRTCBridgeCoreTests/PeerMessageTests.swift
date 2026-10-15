import XCTest

@testable import WebRTCBridgeCore

final class PeerMessageTests: XCTestCase {
  private static let header = #""apiVersion":"openjoystickdriver/v1alpha1""#

  private func frame(_ members: String = "") -> Data {
    Data(#"{\#(Self.header),"kind":"Frame"\#(members)}"#.utf8)
  }

  private func rumble(_ members: String = #","type":"setRumble""#) -> Data {
    Data(#"{\#(Self.header),"kind":"RumbleCommand"\#(members)}"#.utf8)
  }

  func testAValidFrameIsRebuiltFromTheCheckedFields() throws {
    let line = try XCTUnwrap(
      PeerMessage.frame(
        from: frame(
          #","buttons":["south"],"dpad":["up"],"axes":{"left_stick_x":0.5}"#
            + #","holdMilliseconds":60000"#
        )
      )
    )
    XCTAssertEqual(line["buttons"] as? [String], ["south"])
    XCTAssertEqual(line["holdMilliseconds"] as? Int, 60000)
    XCTAssertEqual((line["axes"] as? [String: Double])?["left_stick_x"], 0.5)
  }

  func testAFrameThatIsTooLongIsRejected() {
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    XCTAssertNil(PeerMessage.frame(from: Data((frame().utf8String + padding).utf8)))
  }

  func testAFrameThatIsNotShapedLikeAFrameIsRejected() {
    let rejected = [
      Data("not json".utf8),
      Data("[]".utf8),
      Data(#"{"apiVersion":"other","kind":"Frame"}"#.utf8),
      Data(#"{\#(Self.header),"kind":"Hello"}"#.utf8),
      Data(#"{"kind":"Frame"}"#.utf8),
      frame(#","extra":1"#),
      frame(#","holdMilliseconds":60001"#),
      frame(#","holdMilliseconds":-1"#),
      frame(#","holdMilliseconds":1.5"#),
      frame(#","holdMilliseconds":true"#),
      frame(#","buttons":["nope"]"#),
      frame(#","buttons":["south","south"]"#),
      frame(#","buttons":"south""#),
      frame(#","dpad":["diagonal"]"#),
      frame(#","axes":{"nope":0.5}"#),
      frame(#","axes":{"left_stick_x":true}"#),
      frame(#","axes":{"left_stick_x":"0.5"}"#),
      frame(#","axes":{"left_stick_x":1e999}"#),
    ]
    for data in rejected {
      XCTAssertNil(PeerMessage.frame(from: data), data.utf8String)
    }
  }

  func testAValidRumbleCommandIsAccepted() throws {
    let line = try XCTUnwrap(
      PeerMessage.rumble(
        from: rumble(
          #","type":"setRumble","intensities":{"leftMain":65535},"durationMilliseconds":200"#
        )
      )
    )
    XCTAssertEqual(line["type"] as? String, "setRumble")
    XCTAssertEqual((line["intensities"] as? [String: Int])?["leftMain"], 65535)
    XCTAssertNotNil(PeerMessage.rumble(from: rumble(#","type":"stopRumble""#)))
  }

  func testARumbleCommandThatIsNotShapedLikeOneIsRejected() {
    let rejected = [
      Data("not json".utf8),
      Data(#"{\#(Self.header),"kind":"Frame"}"#.utf8),
      rumble(""),
      rumble(#","type":"explode""#),
      rumble(#","type":"setRumble","extra":1"#),
      rumble(#","type":"setRumble","intensities":{"leftMain":65536}"#),
      rumble(#","type":"setRumble","intensities":{"leftMain":-1}"#),
      rumble(#","type":"setRumble","intensities":{"middle":1}"#),
      rumble(#","type":"setRumble","intensities":{"leftMain":0.5}"#),
      rumble(#","type":"setRumble","durationMilliseconds":-5"#),
    ]
    for data in rejected {
      XCTAssertNil(PeerMessage.rumble(from: data), data.utf8String)
    }
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    XCTAssertNil(PeerMessage.rumble(from: Data((rumble().utf8String + padding).utf8)))
  }

  func testTheMailboxKeepsOnlyTheNewestFrame() {
    let mailbox = FrameMailbox()
    for index in 1...3 { mailbox.post(["n": index]) }
    XCTAssertEqual(mailbox.next(timeout: 1)?["n"] as? Int, 3)
    XCTAssertNil(mailbox.next(timeout: 0.05))
  }

  func testABlobThatIsTooLongIsRefused() {
    let blob = String(repeating: "A", count: PeerMessage.maximumBytes + 1)
    XCTAssertThrowsError(try PeerLink.decode(blob)) { error in
      XCTAssertTrue("\(error)".contains("65536"), "\(error)")
    }
  }
}

extension Data {
  var utf8String: String { String(bytes: self, encoding: .utf8) ?? "" }
}
