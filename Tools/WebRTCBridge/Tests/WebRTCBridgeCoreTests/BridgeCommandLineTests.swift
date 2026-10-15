import XCTest

@testable import WebRTCBridgeCore

final class BridgeCommandLineTests: XCTestCase {
  func testHelpIsRecognisedAlone() {
    XCTAssertEqual(BridgeCommandLine.parse(["--help"]), .help)
  }

  func testHelpWinsOverOtherArguments() {
    XCTAssertEqual(BridgeCommandLine.parse(["--role", "host", "--help"]), .help)
    XCTAssertEqual(BridgeCommandLine.parse(["--bogus", "--help"]), .help)
  }

  func testOptionsAreGroupedByName() {
    XCTAssertEqual(
      BridgeCommandLine.parse(["--role", "host", "--ice-server", "a", "--ice-server", "b"]),
      .options(["role": ["host"], "ice-server": ["a", "b"]])
    )
    XCTAssertEqual(BridgeCommandLine.parse([]), .options([:]))
  }

  func testABadArgumentIsInvalid() {
    XCTAssertEqual(BridgeCommandLine.parse(["role", "host"]), .invalid)
    XCTAssertEqual(BridgeCommandLine.parse(["--role"]), .invalid)
  }
}
