import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// The record's `output.startup` writes, the reports they send, and the transports they apply to.
struct ControllerRecordStartupWriteTests {
  private static let sixaxis =
    #""modes": [{"id": "default", "protocol": {"family": "sony.sixaxis"}}]"#
  private static let enable = #"""
    {"report": {"kind": "feature", "id": 244, "length": 5}, "bytes": [66, 3, 0, 0],
      "transport": "bluetooth-classic"}
    """#

  @Test
  func decodesStartupWritesInOrder() throws {
    let document = try decode(
      "\(Self.sixaxis), \"output\": {\"startup\": [\(Self.enable), "
        + #"{"report": {"kind": "output", "id": 0, "length": 2}, "bytes": [1, 2], "#
        + #""delayMilliseconds": 50}]}"#
    )
    #expect(document.rumbleTemplate == nil)
    #expect(document.startupWrites.count == 2)
    let enable = document.startupWrites[0]
    #expect(enable.transport == .bluetoothClassic && enable.delayMilliseconds == nil)
    #expect(
      enable.write
        == .hidFeature(PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 3, 0, 0]))
    )
    let unnumbered = document.startupWrites[1]
    #expect(unnumbered.transport == nil && unnumbered.delayMilliseconds == 50)
    #expect(
      unnumbered.write
        == .hidOutput(
          PhysicalHIDOutputReport(reportID: 0, bytes: [1, 2], startupDelayMilliseconds: 50)
        )
    )
    #expect(try decode(Self.sixaxis).startupWrites.isEmpty)
  }

  @Test(
    arguments: [
      #"[]"#,
      #"[{"report": {"kind": "input", "id": 1, "length": 3}, "bytes": [0, 0]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0, 0]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 256]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, -1]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0], "#
        + #""delayMilliseconds": 1001}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0], "#
        + #""transport": "proprietary-radio-receiver"}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0], "repeat": 2}]"#,
      "["
        + Array(
          repeating: #"{"report": {"kind": "feature", "id": 1, "length": 2}, "bytes": [0]}"#,
          count: 17
        )
        .joined(separator: ", ") + "]",
    ]
  )
  func rejectsInvalidStartupWrites(startup: String) {
    #expect(throws: DecodingError.self) {
      try decode("\(Self.sixaxis), \"output\": {\"startup\": \(startup)}")
    }
  }

  private static let hidReport =
    #""report": {"kind": "output", "id": 1, "length": 8}, "bytes": [1, 2, 3, 4, 5, 6, 7]"#
  private static let gip = #"{"family": "xbox.gip"}"#

  @Test
  func decodesPhaseAndCRCSeed() throws {
    let document = try decode(
      "\(Self.sixaxis), \"output\": {\"startup\": [{\(Self.hidReport), \"phase\": \"startup\", "
        + #""crc32Seed": 162}]}"#
    )
    #expect(document.startupWrites.first?.phase == .startup)
    #expect(document.startupWrites.first?.crc32Seed == 162)
    #expect(
      try decode("\(Self.sixaxis), \"output\": {\"startup\": [\(Self.enable)]}").startupWrites
        .first?.phase == .activation
    )
  }

  @Test(
    arguments: [
      #""phase": "later""#, #""crc32Seed": 256"#, #""crc32Seed": -1"#, #""delayMilliseconds": -1"#,
      #""variants": ["bluetooth-classic"]"#,
      #""when": {"parameter": "layout", "is": ["Pro"]}"#,
    ]
  )
  func rejectsAMalformedOrDescriptionOnlyHIDField(field: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        "\(Self.sixaxis), \"output\": {\"startup\": [{\(Self.hidReport), \(field)}]}"
      )
    }
  }

  @Test
  func rejectsACRCWriteWithoutRoomForTheTrailer() {
    #expect(throws: DecodingError.self) {
      try decode(
        "\(Self.sixaxis), \"output\": {\"startup\": ["
          + #"{"report": {"kind": "output", "id": 1, "length": 4}, "bytes": [1, 2, 3], "#
          + #""crc32Seed": 1}]}"#
      )
    }
  }

  @Test
  func decodesRawUSBStartupWritesForTheFamiliesThatCarryThem() throws {
    let write =
      #"{"bytes": [1, 2], "endpoint": 2, "timeoutMilliseconds": 500, "#
      + #""delayMilliseconds": 5, "sessionByte": 1, "toleratesRejection": true}"#
    for family in [Self.gip, #"{"family": "nintendo.switch2"}"#] {
      let document = try decode("\"protocol\": \(family), \"output\": {\"startup\": [\(write)]}")
      #expect(document.startupWrites.isEmpty)
      #expect(document.usbStartupWrites.count == 1)
      #expect(document.usbStartupWrites.first?.endpoint == 2)
    }
  }

  @Test(
    arguments: [
      #""endpoint": 0"#, #""endpoint": 128"#, #""timeoutMilliseconds": 0"#,
      #""timeoutMilliseconds": 60001"#, #""delayMilliseconds": 1001"#, #""sessionByte": 64"#,
      #""variants": ["usb"]"#, #""when": {"parameter": "layout", "is": ["Pro"]}"#,
    ]
  )
  func rejectsAMalformedRawUSBStartupWrite(field: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        "\"protocol\": \(Self.gip), \"output\": {\"startup\": [{\"bytes\": [1], \(field)}]}"
      )
    }
  }

  @Test
  func rejectsRawUSBStartupWritesWhereTheFamilyDoesNotCarryThem() {
    for family in [
      #"{"family": "sony.sixaxis"}"#, #"{"family": "vendor.gamesir", "variant": "usb"}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try decode("\"protocol\": \(family), \"output\": {\"startup\": [{\"bytes\": [1]}]}")
      }
    }
  }

  @Test
  func rejectsRawUSBStartupWritesNextToInitializationOrHIDWrites() {
    #expect(throws: DecodingError.self) {
      try decode(
        #""protocol": {"family": "xbox.gip", "initialization": ["xbox.gip/power-on"]}, "#
          + #""output": {"startup": [{"bytes": [1]}]}"#
      )
    }
    #expect(throws: DecodingError.self) {
      try decode(
        "\"protocol\": \(Self.gip), \"output\": {\"startup\": [{\"bytes\": [1]}, "
          + "{\(Self.hidReport)}]}"
      )
    }
  }

  @Test
  func rejectsAnEmptyOutputSection() {
    #expect(throws: DecodingError.self) { try decode("\(Self.sixaxis), \"output\": {}") }
  }

  /// Startup writes go through IOHID, so a raw-USB family cannot name them.
  @Test(
    arguments: [
      #"{"family": "xbox.gip"}"#, #"{"family": "xbox.xusb", "variant": "wired"}"#,
      #"{"family": "vendor.gamesir", "variant": "usb"}"#,
    ]
  )
  func rejectsStartupWritesOnRawUSBFamilies(protocolInfo: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo)}], \"output\": {\"startup\": [\(Self.enable)]}"
      )
    }
  }

  @Test
  func appliesOnlyToItsTransport() throws {
    let report = ControllerTemplateReport(kind: .feature, reportID: 1, length: 2)
    let bluetooth = try RecordStartupWrite(report: report, bytes: [0], transport: .bluetoothClassic)
    #expect(bluetooth.applies(to: .bluetoothClassic))
    #expect(!bluetooth.applies(to: .usb) && !bluetooth.applies(to: nil))
    let any = try RecordStartupWrite(report: report, bytes: [0])
    #expect(any.applies(to: .usb) && any.applies(to: .bluetoothLE) && any.applies(to: nil))
  }

  /// Both Sixaxis identities carry the Bluetooth enable report `hid-sony.c` sends.
  @Test(arguments: [UInt16(0x0268), 0x0523])
  func sixaxisRecordsEnableBluetooth(productID: UInt16) throws {
    let vendorID: UInt16 = productID == 0x0268 ? 0x054C : 0x2563
    // The DS3 holds the report in its `bluetooth` mode, which a Bluetooth link selects; the other
    // identity still holds it as a record-level write limited to Bluetooth.
    let modeID: String? = productID == 0x0268 ? "bluetooth" : nil
    let record = try #require(
      DeviceCatalog().record(
        for: ControllerModelID(vendorID: vendorID, productID: productID),
        modeID: modeID
      )
    )
    #expect(record.physicalProtocolID == .sonySixaxis)
    let expectedTransports: [PhysicalTransport?] = productID == 0x0268 ? [nil] : [.bluetoothClassic]
    #expect(record.startupWrites.map(\.transport) == expectedTransports)
    #expect(
      record.startupWrites.map(\.write) == [
        .hidFeature(
          PhysicalHIDOutputReport(
            reportID: ProtocolPacketFixtures.DS3.bluetoothOperationalReportID,
            bytes: ProtocolPacketFixtures.DS3.bluetoothOperationalReport
          )
        )
      ]
    )
  }

  /// Decodes a record for 2563:0575 whose remaining top-level fields are `fields`.
  private func decode(_ fields: String) throws -> ControllerRecordDocument {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
      "vendorID": 9571, "productID": 1397, \
      \(fields)}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }
}
