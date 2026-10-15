import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Button, axis and hat usages as typed data: how a record declares them and what each reads.
struct HIDUsageMapTests {
  private func element(
    page: UInt32 = 1,
    usage: UInt32,
    _ value: Int,
    range: ClosedRange<Int> = 0...255,
    reportID: UInt32? = nil
  ) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: range.lowerBound,
      logicalMaximum: range.upperBound,
      integerValue: value,
      reportID: reportID
    )
  }

  private func makeDriver(_ entries: String, reportID: Int? = nil) throws -> HIDDescriptorDriver {
    let document = try decode(entries, reportID: reportID)
    return HIDDescriptorDriver(
      model: ControllerModelID(vendorID: 0xFFFE, productID: 1),
      usageMap: document.hidUsageMap
    )
  }

  private func state(_ driver: HIDDescriptorDriver, _ value: HIDElementValue) -> ControllerState? {
    driver.parse(elementValue: value, receivedAt: MonotonicTimestamp(nanoseconds: 0))?.state
  }

  private func decode(
    _ entries: String,
    reportID: Int? = nil,
    family: String = "hid.descriptor",
    key: String = "hidUsageMap"
  ) throws -> ControllerRecordDocument {
    let report = reportID.map { "\"reportID\": \($0)," } ?? ""
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
       "vendorID": 65534, "productID": 1, "protocol": {"family": "\(family)"},
       "input": {"\(key)": {\(report) "usages": [\(entries)]}}}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }

  // MARK: - Buttons

  @Test
  func aButtonUsagePressesItsControlWhileNonzero() throws {
    let driver = try makeDriver(#"{"kind":"button","page":9,"usage":3,"control":"West"}"#)
    #expect(
      state(driver, element(page: 9, usage: 3, 1, range: 0...1))?.pressed.contains(.west)
        == true
    )
    #expect(
      state(driver, element(page: 9, usage: 3, 0, range: 0...1))?.pressed.contains(.west)
        == false
    )
    #expect(state(driver, element(page: 9, usage: 4, 1, range: 0...1)) == nil)
    #expect(state(driver, element(page: 8, usage: 3, 1, range: 0...1)) == nil)
  }

  @Test
  func aReportIDRestrictsTheMapToThatReport() throws {
    let driver = try makeDriver(
      #"{"kind":"button","page":9,"usage":1,"control":"South"}"#,
      reportID: 6
    )
    #expect(state(driver, element(page: 9, usage: 1, 1, range: 0...1, reportID: 5)) == nil)
    #expect(state(driver, element(page: 9, usage: 1, 1, range: 0...1, reportID: nil)) == nil)
    #expect(
      state(driver, element(page: 9, usage: 1, 1, range: 0...1, reportID: 6))?.pressed.contains(
        .south
      )
        == true
    )
  }

  // MARK: - Axes

  private func axisEntry(control: String, _ options: String = "") -> String {
    #"{"kind":"axis","page":1,"usage":48,"control":"\#(control)"\#(options)}"#
  }

  @Test
  func aStickAxisScalesTheLogicalRangeToMinusOneToOne() throws {
    let driver = try makeDriver(axisEntry(control: "LeftStickX"))
    #expect(state(driver, element(usage: 48, 255))?.leftStick.x.normalized == 1)
    #expect(state(driver, element(usage: 48, 0))?.leftStick.x.normalized == -1)
    #expect(
      abs(try #require(state(driver, element(usage: 48, 128))?.leftStick.x.normalized)) < 0.01
    )
  }

  @Test
  func anInvertedStickNegatesTheAxis() throws {
    let driver = try makeDriver(axisEntry(control: "LeftStickX", #","inverted":true"#))
    #expect(state(driver, element(usage: 48, 255))?.leftStick.x.normalized == -1)
    #expect(state(driver, element(usage: 48, 0))?.leftStick.x.normalized == 1)
  }

  @Test
  func anAxisRangeOverridesTheElementsLogicalRange() throws {
    let driver = try makeDriver(
      axisEntry(control: "LeftStickX", #","range":{"min":0,"max":100}"#)
    )
    // The element declares 0...255; the record says full deflection is 100.
    #expect(state(driver, element(usage: 48, 100))?.leftStick.x.normalized == 1)
    #expect(state(driver, element(usage: 48, 200))?.leftStick.x.normalized == 1)
    #expect(state(driver, element(usage: 48, 0))?.leftStick.x.normalized == -1)
  }

  @Test
  func aStickDeadZoneReadsZeroInsideAndRescalesOutside() throws {
    let driver = try makeDriver(
      axisEntry(control: "LeftStickX", #","range":{"min":-100,"max":100},"deadZone":0.2"#)
    )
    let wide = -100...100
    #expect(state(driver, element(usage: 48, 10, range: wide))?.leftStick.x.normalized == 0)
    #expect(state(driver, element(usage: 48, -20, range: wide))?.leftStick.x.normalized == 0)
    #expect(state(driver, element(usage: 48, 100, range: wide))?.leftStick.x.normalized == 1)
    let half = try #require(
      state(driver, element(usage: 48, 60, range: wide))?.leftStick.x.normalized
    )
    #expect(abs(half - 0.5) < 0.001)
  }

  @Test
  func aTriggerAxisReadsZeroToOneAndSupportsInversionAndDeadZone() throws {
    let plain = try makeDriver(axisEntry(control: "RightTrigger"))
    #expect(state(plain, element(usage: 48, 255))?.rightTrigger.normalized == 1)
    #expect(state(plain, element(usage: 48, 0))?.rightTrigger.normalized == 0)

    let inverted = try makeDriver(axisEntry(control: "LeftTrigger", #","inverted":true"#))
    #expect(state(inverted, element(usage: 48, 0))?.leftTrigger.normalized == 1)
    #expect(state(inverted, element(usage: 48, 255))?.leftTrigger.normalized == 0)

    let dead = try makeDriver(axisEntry(control: "LeftTrigger", #","deadZone":0.5"#))
    #expect(state(dead, element(usage: 48, 100))?.leftTrigger.normalized == 0)
    #expect(state(dead, element(usage: 48, 255))?.leftTrigger.normalized == 1)
  }

  /// Spec scenario "Swapped trigger axes": a record maps usage Z to the right trigger.
  @Test
  func swappedTriggerAxesFollowTheRecord() throws {
    let driver = try makeDriver(
      #"{"kind":"axis","page":1,"usage":50,"control":"RightTrigger"},"#
        + #"{"kind":"axis","page":1,"usage":53,"control":"LeftTrigger"}"#
    )
    let pulled = state(driver, element(usage: 50, 255))
    #expect(pulled?.rightTrigger.normalized == 1)
    #expect(pulled?.leftTrigger.normalized == 0)
  }

  @Test
  func anAxisWithNoSpanReadsZero() throws {
    let driver = try makeDriver(axisEntry(control: "LeftStickX"))
    #expect(state(driver, element(usage: 48, 5, range: 0...0))?.leftStick.x.normalized == 0)
  }

  // MARK: - Hats

  private let hatEntry = #"{"kind":"hat","page":1,"usage":57}"#

  @Test
  func aHatReadsFromTheElementsLogicalMinimumByDefault() throws {
    let driver = try makeDriver(hatEntry)
    #expect(state(driver, element(usage: 57, 0, range: 0...7))?.hat == .north)
    #expect(state(driver, element(usage: 57, 3, range: 0...7))?.hat == .southEast)
    #expect(state(driver, element(usage: 57, 1, range: 1...8))?.hat == .north)
    #expect(state(driver, element(usage: 57, 8, range: 1...8))?.hat == .northWest)
    #expect(state(driver, element(usage: 57, 15, range: 0...7))?.hat == .neutral)
  }

  @Test(arguments: [(0, 8), (1, 9)])
  func aHatRangeNamesWhereNorthIs(first: Int, nullValue: Int) throws {
    let range = "{\"min\":\(first),\"max\":\(first + 7)}"
    let driver = try makeDriver(
      #"{"kind":"hat","page":1,"usage":57,"range":\#(range)}"#
    )
    #expect(state(driver, element(usage: 57, first, range: 0...15))?.hat == .north)
    #expect(state(driver, element(usage: 57, first + 4, range: 0...15))?.hat == .south)
    #expect(state(driver, element(usage: 57, first + 7, range: 0...15))?.hat == .northWest)
    #expect(state(driver, element(usage: 57, nullValue, range: 0...15))?.hat == .neutral)
  }

  // MARK: - Rejections

  @Test
  func theDecoderRejectsInvalidUsages() {
    let button = #"{"kind":"button","page":9,"usage":1,"control":"South"}"#
    let invalid = [
      // The same usage twice.
      button + "," + button,
      // A button cannot drive a stick axis or the dpad.
      #"{"kind":"button","page":9,"usage":1,"control":"LeftStickX"}"#,
      #"{"kind":"button","page":9,"usage":1,"control":"DpadUp"}"#,
      // An axis needs a stick axis or trigger.
      #"{"kind":"axis","page":1,"usage":48,"control":"South"}"#,
      #"{"kind":"axis","page":1,"usage":48,"control":"DpadUp"}"#,
      // A hat has no control: it is the four dpad ids.
      #"{"kind":"hat","page":1,"usage":57,"control":"DpadUp"}"#,
      // Ranges must have min below max, and a hat range is 0...7 or 1...8.
      #"{"kind":"axis","page":1,"usage":48,"control":"LeftStickX","range":{"min":5,"max":5}}"#,
      #"{"kind":"axis","page":1,"usage":48,"control":"LeftStickX","range":{"min":9,"max":1}}"#,
      #"{"kind":"hat","page":1,"usage":57,"range":{"min":2,"max":9}}"#,
      // A dead zone is above 0 and below 1.
      #"{"kind":"axis","page":1,"usage":48,"control":"LeftStickX","deadZone":0}"#,
      #"{"kind":"axis","page":1,"usage":48,"control":"LeftStickX","deadZone":1}"#,
      #"{"kind":"axis","page":1,"usage":48,"control":"LeftStickX","deadZone":-0.1}"#,
      // Fields that belong to another kind, unknown kinds and unknown fields.
      #"{"kind":"button","page":9,"usage":1,"control":"South","deadZone":0.1}"#,
      #"{"kind":"hat","page":1,"usage":57,"inverted":true}"#,
      #"{"kind":"slider","page":1,"usage":48,"control":"LeftStickX"}"#,
      #"{"kind":"button","page":9,"usage":1,"control":"South","extra":1}"#,
      // Page and usage bounds.
      #"{"kind":"button","page":0,"usage":1,"control":"South"}"#,
      #"{"kind":"button","page":9,"usage":65536,"control":"South"}"#,
      "",
    ]
    for entries in invalid {
      #expect(throws: (any Error).self, "\(entries)") { try decode(entries) }
    }
    #expect(throws: (any Error).self) { try decode(button, reportID: 0) }
    #expect(throws: (any Error).self) { try decode(button, reportID: 256) }
  }

  @Test
  func aUsageMapBelongsToHIDDescriptorRecordsOnly() throws {
    let button = #"{"kind":"button","page":9,"usage":1,"control":"South"}"#
    #expect(try decode(button).hidUsageMap?.entries.count == 1)
    #expect(throws: (any Error).self) { try decode(button, family: "sony.dualshock4") }
    #expect(throws: (any Error).self) { try decode(button, family: "hid.report-layout") }
    #expect(throws: (any Error).self) { try decode(button, key: "descriptorShapes") }
  }
}
