import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Task 9.1d: the keep-alive interval and fixed writes of GameSir, GIP, Switch 2 and the Steam
/// Deck and Triton come from `defaults.output.keepAlive` in the family's description. The decoder
/// accepts and rejects the documents the Python validator does (the protocol description tests),
/// and each driver sends the bytes, at the interval, that it sent before the move.
private let writes500 = #"{"intervalMilliseconds": 500, "writes": ["#
private let hidWriteHead =
  #"{"report": {"kind": "feature", "id": 1, "length": 4}, "bytes": [1, 2, 3], "#
private let nineWrites = Array(repeating: keepAliveUSBWrite, count: 9).joined(separator: ",")
private let keepAliveUSBWrite = #"{"bytes": [3, 32, 0, 3], "sessionByte": 2}"#

struct KeepAliveDescriptionTests {
  private static let usbWrite = keepAliveUSBWrite
  private static let hidWrite =
    #"{"report": {"kind": "feature", "id": 1, "length": 4}, "bytes": [1, 2, 3]}"#

  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", "endpoints": {"in": 130, "out": 2}, \(body)}
      """
    return try ProtocolDescription.decode(
      Data(json.utf8),
      protocolID: family,
      fileName: "\(family.rawValue).json"
    )
  }

  private func rejection(family: PhysicalProtocolID, _ body: String) -> ProtocolDescriptionProblem?
  {
    do {
      _ = try decode(family: family, body)
      return nil
    } catch { return error }
  }

  private func gip(_ keepAlive: String, tuning: String = "") -> String {
    #""rawUSB": true, "rawUSBTuningKeys": ["keepAliveIntervalMs"], "defaults": {"#
      + (tuning.isEmpty ? "" : #""tuning": \#(tuning), "#)
      + #""output": {"keepAlive": \#(keepAlive)}}"#
  }

  // MARK: - Decoder

  @Test
  func acceptsAKeepAliveWithItsIntervalAndWrites() throws {
    let description = try decode(
      family: .xboxGIP,
      gip(#"{"intervalMilliseconds": 4000, "writes": [\#(Self.usbWrite)]}"#)
    )
    #expect(description.keepAlive?.intervalMilliseconds == 4000)
    #expect(description.keepAliveWrites(variant: .usb).count == 1)
    let intervalOnly = try decode(family: .xboxGIP, gip(#"{"intervalMilliseconds": 1}"#))
    #expect(intervalOnly.keepAlive?.intervalMilliseconds == 1)
    #expect(intervalOnly.keepAliveWrites(variant: .usb).isEmpty)
  }

  @Test(
    arguments: [
      "{}", #"{"writes": [\#(keepAliveUSBWrite)]}"#, #"{"intervalMilliseconds": 0}"#,
      #"{"intervalMilliseconds": 60001}"#, #"{"intervalMilliseconds": 1.5}"#,
      #"{"intervalMilliseconds": "500"}"#, #"{"intervalMilliseconds": 500, "unknown": 1}"#,
      #"{"intervalMilliseconds": 500, "writes": []}"#,
      writes500 + nineWrites + "]}",
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": []}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "sessionByte": 64}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "endpoint": 0}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "variants": []}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "resendTuning": "x"}]}"#,
      writes500 + #"{"bytes": [1], "resendTuning": "keepAliveIntervalMs"}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "delayMilliseconds": 5}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "toleratesRejection": true}]}"#,
      writes500 + #"{"bytes": [1], "when": {"parameter": "layout", "is": ["Pro"]}}]}"#,
    ]
  )
  func rejectsAMalformedKeepAlive(keepAlive: String) {
    #expect(
      rejection(family: .xboxGIP, gip(keepAlive))?.code == .invalidProtocolDescription,
      "\(keepAlive)"
    )
  }

  @Test(
    arguments: [
      hidWriteHead + #""phase": "startup"}"#,
      hidWriteHead + #""delayMilliseconds": 5}"#,
      hidWriteHead + #""transport": "usb"}"#,
      #"{"report": {"kind": "feature", "id": 1, "length": 4}, "bytes": [1, 2, 3], "crc32Seed": 1}"#,
    ]
  )
  func rejectsStartupOnlyMembersInAKeepAliveWrite(write: String) {
    let body =
      #""tuningKeys": ["keepAliveIntervalMs"], "defaults": {"output": {"keepAlive": "#
      + #"{"intervalMilliseconds": 500, "writes": [\#(write)]}}}"#
    #expect(rejection(family: .sonyDualSense, body)?.code == .invalidProtocolDescription)
  }

  @Test
  func rejectsAKeepAliveTheFamilyCannotRun() {
    let interval = #"{"intervalMilliseconds": 500}"#
    // The family reads no keep-alive interval.
    #expect(
      rejection(
        family: .xboxGIP,
        #""rawUSB": true, "defaults": {"output": {"keepAlive": \#(interval)}}"#
      )?
      .code == .invalidProtocolDescription
    )
    // A HID write for a raw-USB family, and a raw-USB write for a HID family.
    #expect(
      rejection(
        family: .xboxGIP,
        gip(#"{"intervalMilliseconds": 500, "writes": [\#(Self.hidWrite)]}"#)
      )?
      .code == .invalidProtocolDescription
    )
    let hidFamily =
      #""tuningKeys": ["keepAliveIntervalMs"], "defaults": {"output": {"keepAlive": "#
      + #"{"intervalMilliseconds": 500, "writes": [\#(Self.usbWrite)]}}}"#
    #expect(rejection(family: .sonyDualSense, hidFamily)?.code == .invalidProtocolDescription)
    // A variant the family lacks.
    let variant =
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": [1], "variants": ["wired"]}]}"#
    #expect(rejection(family: .xboxGIP, gip(variant))?.code == .unknownProtocolVariant)
    // A cadence key the family does not default.
    let cadence =
      writes500 + #"{"bytes": [1], "resendTuning": "lizardResendTicks"}]}"#
    #expect(rejection(family: .xboxGIP, gip(cadence))?.code == .invalidProtocolDescription)
    // Records never carry keep-alive writes.
    #expect(
      rejection(
        family: .xboxXID,
        #""rawUSB": true, "defaults": {"output": {"keepAlive": \#(interval)}}"#
      ) != nil
    )
  }

  @Test
  func rejectsTheKeepAliveIntervalAsATuningDefault() {
    let keepAlive = #"{"intervalMilliseconds": 500}"#
    #expect(
      rejection(family: .xboxGIP, gip(keepAlive, tuning: #"{"keepAliveIntervalMs": 500}"#))?.code
        == .invalidProtocolDescription
    )
    let variantTuning =
      #""rawUSB": true, "rawUSBTuningKeys": ["keepAliveIntervalMs"], "#
      + #""defaults": {"variants": {"usb": {"tuning": {"keepAliveIntervalMs": 500}}}}"#
    #expect(rejection(family: .xboxGIP, variantTuning)?.code == .invalidProtocolDescription)
  }

  // MARK: - Drivers keep their bytes and interval

  @Test
  func gameSirSendsItsHeartbeatsEvery500Milliseconds() {
    let enhanced = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    #expect(enhanced.sessionPlan.hidKeepAliveIntervalNanoseconds == 500_000_000)
    let heartbeat = enhanced.keepAliveWrites().hidOutputs
    #expect(heartbeat.map(\.reportID) == [0x0F])
    #expect(heartbeat.map(\.bytes) == [[0x0F, 0xF2] + [UInt8](repeating: 0, count: 62)])

    let g7 = GameSirDriver(protocol: .g7ProUSB)
    #expect(g7.sessionPlan.usbKeepAliveIntervalNanoseconds == 500_000_000)
    for sequence in 1...3 {
      let packets = g7.keepAliveWrites().usbPackets
      #expect(
        packets.map(\.bytes)
          == [[0x0F, 0x00, UInt8(sequence), 0x02, 0xF2, 0x00] + [UInt8](repeating: 0, count: 58)]
      )
      #expect(packets.map(\.endpoint) == [g7.outEndpoint])
      #expect(packets.map(\.timeoutMilliseconds) == [g7.usbTimeoutMilliseconds])
    }
  }

  @Test
  func gipSendsItsStatusPacketEvery4SecondsAndNoneWhenDisabled() {
    let driver = GIPDriver()
    #expect(driver.sessionPlan.usbKeepAliveIntervalNanoseconds == 4_000_000_000)
    let first = driver.keepAliveWrites().usbPackets
    let second = driver.keepAliveWrites().usbPackets
    #expect(first.map(\.bytes) == [[0x03, 0x20, 1, 0x03, 0x00, 0x00, 0x00]])
    #expect(second.map(\.bytes) == [[0x03, 0x20, 2, 0x03, 0x00, 0x00, 0x00]])
    #expect(first.map(\.endpoint) == [PhysicalProtocolID.xboxGIP.descriptionOutputEndpoint])
    #expect(GIPDriver(keepAlivePolicy: .disabled).keepAliveWrites().isEmpty)
    #expect(
      GIPDriver(keepAlivePolicy: .disabled).sessionPlan.usbKeepAliveIntervalNanoseconds == nil
    )
  }

  @Test
  func switch2KeepsItsIntervalInTheDescription() {
    let description = PhysicalProtocolID.nintendoSwitch2.protocolDescription
    #expect(description.keepAlive?.intervalMilliseconds == 12)
    #expect(description.keepAliveWrites(variant: .usb).isEmpty)
    let driver = Switch2Driver(layout: .pro, link: .usb)
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 12_000_000)
  }

  @Test
  func steamDeckSendsTheLizardWatchdogEverySecond() {
    let driver = SteamDeckDriver()
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 1_000_000_000)
    let features = driver.keepAliveWrites().hidFeatures
    #expect(features.map(\.reportID) == [0, 0])
    #expect(
      features.map(\.bytes) == [
        [0x81] + [UInt8](repeating: 0, count: 63),
        [0x87, 0x03, 0x08, 0x07, 0x00, 0x00] + [UInt8](repeating: 0, count: 58),
      ]
    )
  }

  @Test
  func steamTritonResendsLizardModeOffOnlyEvery75thTick() {
    let driver = SteamTritonDriver()
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 40_000_000)
    let lizardOff =
      [0x01, 0x87, 0x03, 0x09, 0x00, 0x00].map(UInt8.init) + [UInt8](repeating: 0, count: 58)
    let ticks = (0..<76).map { _ in driver.keepAliveWrites().hidFeatures }
    #expect(ticks.enumerated().filter { !$0.element.isEmpty }.map(\.offset) == [0, 75])
    #expect(ticks[0].map(\.bytes) == [lizardOff])
    #expect(ticks[0].map(\.reportID) == [1])
  }
}
