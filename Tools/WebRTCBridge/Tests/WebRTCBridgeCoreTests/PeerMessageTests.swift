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
          #","buttons":["South"],"dpad":["up"],"axes":{"LeftStickX":0.5}"#
            + #","holdMilliseconds":60000"#
        )
      )
    )
    XCTAssertEqual(line["buttons"] as? [String], ["South"])
    XCTAssertEqual(line["holdMilliseconds"] as? Int, 60000)
    XCTAssertEqual((line["axes"] as? [String: Double])?["LeftStickX"], 0.5)
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
      frame(#","buttons":["nope"]"#), frame(#","buttons":["south"]"#),
      frame(#","axes":{"left_stick_x":0.5}"#),
      frame(#","buttons":["South","South"]"#),
      frame(#","buttons":"South""#),
      frame(#","dpad":["diagonal"]"#),
      frame(#","axes":{"nope":0.5}"#),
      frame(#","axes":{"LeftStickX":true}"#),
      frame(#","axes":{"LeftStickX":"0.5"}"#),
      frame(#","axes":{"LeftStickX":1e999}"#),
    ]
    for data in rejected {
      XCTAssertNil(PeerMessage.frame(from: data), data.utf8String)
    }
  }

  private static let allIntensities =
    #""intensities":{"leftMain":65535,"rightMain":0,"leftTrigger":1,"rightTrigger":2,"#
    + #""leftHaptic":3,"rightHaptic":4}"#

  func testAValidRumbleCommandIsAccepted() throws {
    let line = try XCTUnwrap(
      PeerMessage.rumble(
        from: rumble(#","type":"setRumble",\#(Self.allIntensities),"durationMilliseconds":5000"#)
      )
    )
    XCTAssertEqual(line["type"] as? String, "setRumble")
    XCTAssertEqual((line["intensities"] as? [String: Int])?["leftMain"], 65535)
    XCTAssertEqual(line["durationMilliseconds"] as? Int, 5000)
    XCTAssertNotNil(
      PeerMessage.rumble(from: rumble(#","type":"setRumble",\#(Self.allIntensities)"#))
    )
    XCTAssertNotNil(PeerMessage.rumble(from: rumble(#","type":"stopRumble""#)))
  }

  func testARumbleCommandThatIsNotShapedLikeOneIsRejected() {
    let all = Self.allIntensities
    let rejected = [
      Data("not json".utf8),
      Data(#"{\#(Self.header),"kind":"Frame"}"#.utf8),
      Data(#"{"apiVersion":"other","kind":"RumbleCommand","type":"stopRumble"}"#.utf8),
      rumble(""),
      rumble(#","type":"explode""#),
      rumble(#","type":"setRumble",\#(all),"extra":1"#),
      rumble(#","type":"setRumble",\#(all),"durationMilliseconds":5001"#),
      rumble(#","type":"setRumble",\#(all),"durationMilliseconds":-5"#),
      rumble(#","type":"setRumble""#),
      rumble(#","type":"setRumble","intensities":{"leftMain":1}"#),
      rumble(#","type":"setRumble","intensities":{"middle":1}"#),
      rumble(#","type":"stopRumble","durationMilliseconds":0"#),
      rumble(#","type":"stopRumble","intensities":{}"#),
      rumble(#","type":"stopRumble","extra":1"#),
    ]
    for data in rejected {
      XCTAssertNil(PeerMessage.rumble(from: data), data.utf8String)
    }
    let outOfRange = [
      all.replacingOccurrences(of: "65535", with: "65536"),
      all.replacingOccurrences(of: "\"rightMain\":0", with: "\"rightMain\":-1"),
      all.replacingOccurrences(of: "\"rightMain\":0", with: "\"rightMain\":0.5"),
    ]
    for intensities in outOfRange {
      XCTAssertNil(PeerMessage.rumble(from: rumble(#","type":"setRumble",\#(intensities)"#)))
    }
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    XCTAssertNil(
      PeerMessage.rumble(from: Data((rumble(#","type":"stopRumble""#).utf8String + padding).utf8))
    )
  }

  func testTheMailboxKeepsOnlyTheNewestFrame() {
    let mailbox = FrameMailbox()
    for index in 1...3 { mailbox.post(["n": index]) }
    XCTAssertEqual(mailbox.next(timeout: 1)?["n"] as? Int, 3)
    XCTAssertNil(mailbox.next(timeout: 0.05))
  }

  func testAPostThatRacesTheTimeoutIsNeitherLostNorRepeated() {
    let mailbox = FrameMailbox()
    var received = 0
    for index in 0..<300 {
      Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 0.0005)
        mailbox.post(["n": index])
      }
      var got = false
      while !got { got = mailbox.next(timeout: 0.0005) != nil }
      received += 1
      // Nothing is left over: the next wait lasts for its whole timeout.
      let start = Date()
      XCTAssertNil(mailbox.next(timeout: 0.01))
      XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.009)
    }
    XCTAssertEqual(received, 300)
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
