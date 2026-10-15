import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The bytes and sequence numbers the GIP driver stamps on each named startup packet of
/// `defaults.session.namedPackets` in `xbox.gip.json`.
struct GIPStartupPacketBytesTests {
  private static let identifiers = [
    "xbox.gip/power-on", "xbox.gip/s-init", "xbox.gip/enable-extra-input", "xbox.gip/hori-ack",
    "xbox.gip/led-on", "xbox.gip/auth-done", "xbox.gip/rumble-begin", "xbox.gip/rumble-end",
  ]

  private func driver(_ identifiers: [String]) -> GIPDriver {
    GIPDriver(startupPackets: identifiers)
  }

  private func hex(_ write: PhysicalOutputWrite) -> String {
    guard case .usb(let packet, _) = write else { return "other" }
    return "\(packet.endpoint):" + packet.bytes.map { String(format: "%02x", $0) }.joined()
  }

  private func startup(_ identifiers: [String]) -> [String] {
    driver(identifiers).startupWrites().map(hex)
  }

  /// Each packet alone, in a fresh driver: the first sequence number of its command counter.
  private static let alone: [String: String] = [
    "xbox.gip/power-on": "2:0520010100",
    "xbox.gip/s-init": "2:0520010f06",
    "xbox.gip/enable-extra-input": "2:4d1001020700",
    "xbox.gip/hori-ack": "2:012001090004203a0000008000",
    "xbox.gip/led-on": "2:0a200103000114",
    "xbox.gip/auth-done": "2:062001020100",
    "xbox.gip/rumble-begin": "2:09000109000f00001d1dff0000",
    "xbox.gip/rumble-end": "2:09000109000f00000000000000",
  ]

  private static let all = [
    "2:0520010100", "2:0520020f06", "2:4d1001020700", "2:012003090004203a0000008000",
    "2:0a200403000114", "2:062001020100", "2:09000209000f00001d1dff0000",
    "2:09000309000f00000000000000",
  ]

  private static let reversed = [
    "2:09000109000f00000000000000", "2:09000209000f00001d1dff0000", "2:062001020100",
    "2:0a200103000114", "2:012002090004203a0000008000", "2:4d1003020700", "2:0520030f06",
    "2:0520040100",
  ]

  @Test
  func testEachNamedPacketAloneCarriesTheSameBytes() {
    for identifier in Self.identifiers {
      #expect(startup([identifier]) == [Self.alone[identifier]], "\(identifier)")
    }
  }

  @Test
  func testAllNamedPacketsShareCommandCountersInListOrder() {
    #expect(startup(Self.identifiers) == Self.all)
    #expect(startup(Self.identifiers.reversed()) == Self.reversed)
  }

  @Test
  func testARepeatedPacketTakesTheNextSequenceNumber() {
    let twice = startup(["xbox.gip/power-on", "xbox.gip/power-on", "xbox.gip/s-init"])
    #expect(twice == ["2:0520010100", "2:0520020100", "2:0520030f06"])
  }

  @Test
  func testSequenceNumbersContinueAcrossStartupsAndIntoTheKeepAlive() {
    let gip = driver(Self.identifiers)
    #expect(gip.startupWrites().map(hex) == Self.all)
    #expect(
      gip.startupWrites().map(hex) == [
        "2:0520050100", "2:0520060f06", "2:4d1004020700", "2:012007090004203a0000008000",
        "2:0a200803000114", "2:062002020100", "2:09000509000f00001d1dff0000",
        "2:09000609000f00000000000000",
      ]
    )
    #expect(gip.keepAliveWrites().map(hex) == ["2:03200903000000"])
  }

  @Test
  func testTheDefaultStartupIsPowerOnLedOnAuthDone() {
    #expect(
      GIPDriver().startupWrites().map(hex)
        == ["2:0520010100", "2:0a200203000114", "2:062001020100"]
    )
  }
}
