import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// One valid button, for cases that vary only another part of the layout.
private let button = #"{"control": "South", "byte": 1, "mask": 1}"#

/// Layouts the symmetric axis and table hat rules reject.
private let invalidSymmetricAxesAndTableHats: [String] = [
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "byte": 1, "symmetric": true}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "byte": 1, "signed": true, "#
    + #""min": 0, "max": 127, "symmetric": true}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "hat": [{"encoding": "Table", "byte": 1, "mask": 15, "#
    + #""values": {}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "hat": [{"encoding": "Table", "byte": 1, "mask": 15, "#
    + #""values": {"16": "North"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "hat": [{"encoding": "Table", "byte": 1, "mask": 15, "#
    + #""values": {"01": "North"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "hat": [{"encoding": "Table", "byte": 1, "mask": 15, "#
    + #""values": {"1": "Neutral"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "hat": [{"encoding": "Table", "byte": 1, "mask": 15, "#
    + #""values": {"1": "up"}}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "hat": [{"encoding": "Table", "byte": 1, "mask": 15}]}"#,
]

/// Layouts the decoder rejects.
private let invalidLayouts: [String] = [
  // Report bounds.
  #"{"report": {"id": 0, "length": {"atLeast": 2}}, "buttons": [\#(button)]}"#,
  #"{"report": {"id": 256, "length": {"atLeast": 2}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 0}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 65}}, "buttons": [\#(button)]}"#,
  #"{"report": {"id": 1, "length": {"atLeast": 1}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"exactly": 0}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"exactly": 65}}, "buttons": [\#(button)]}"#,
  #"{"report": {"id": 1, "length": {"exactly": 1}}, "buttons": [\#(button)]}"#,
  // The length rule names exactly one of atLeast and exactly.
  #"{"report": {"length": 2}, "buttons": [\#(button)]}"#,
  #"{"report": {}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 2, "exactly": 2}}, "buttons": [\#(button)]}"#,
  #"{"report": {"length": {"atLeast": 2}, "exactLength": true}, "buttons": [\#(button)]}"#,
  // Fields.
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "byte": 1, "mask": 0}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "byte": 1, "mask": 256}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "byte": 2, "mask": 1}]}"#,
  #"{"report": {"id": 1, "length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "South", "byte": 0, "mask": 1}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "DpadUp", "byte": 1, "mask": 1}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""buttons": [{"control": "LeftStickX", "byte": 1, "mask": 1}]}"#,
  // Hat.
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "EightWay", "byte": 1, "mask": 3}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "EightWay", "byte": 1, "mask": 11}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""hat": [{"encoding": "4-way", "byte": 1, "mask": 15}]}"#,
  // Axes.
  #"{"report": {"length": {"atLeast": 2}}, "axes": [{"control": "South", "byte": 1}]}"#,
  #"{"report": {"length": {"atLeast": 3}}, "axes": [{"control": "LeftStickX", "byte": 1}, "#
    + #"{"control": "LeftStickX", "byte": 2}]}"#,
  #"{"report": {"length": {"atLeast": 3}}, "#
    + #""axes": [{"control": "LeftStickX", "byte": 1, "bits": 12}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "byte": 1, "bits": 16}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "byte": 1, "min": 10, "max": 11}]}"#,
  #"{"report": {"length": {"atLeast": 2}}, "#
    + #""axes": [{"control": "LeftStickX", "byte": 1, "max": 256}]}"#,
  // Triggers and shape.
  #"{"report": {"length": {"atLeast": 2}}, "leftTrigger": {}}"#,
  #"{"report": {"length": {"atLeast": 2}}}"#,
  #"{"report": {"length": {"atLeast": 2}}, "buttons": []}"#,
  #"{"report": {"length": {"atLeast": 2}}, "buttons": [\#(button)], "touchpad": {}}"#,
  #"{"report": {"length": {"atLeast": 2}, "endpoint": 1}, "buttons": [\#(button)]}"#,
]

@Suite
struct ControllerInputLayoutTests {
  @Test
  func repeatedButtonFieldsAreAlternatives() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 2}}, "buttons": [
        {"control": "North", "byte": 0, "mask": 8},
        {"control": "North", "byte": 1, "mask": 128}
      ]}
      """
    )
    #expect(layout.buttons.count == 1)
    #expect(
      layout.buttons.first?.fields == [
        ReportBitField(byte: 0, mask: 8), ReportBitField(byte: 1, mask: 128),
      ]
    )
    #expect(layout.controls == [.north])
  }

  @Test
  func exactlyIgnoresLongerReportsAndAtLeastAcceptsThem() throws {
    let exact = ReportLayoutDriver(
      layout: try inputLayout(
        """
        {"report": {"length": {"exactly": 2}},
         "buttons": [{"control": "South", "byte": 1, "mask": 1}]}
        """
      )
    )
    #expect(try exact.parseReport(Data([0, 1]))?.state.pressed == [.south])
    #expect(try exact.parseReport(Data([0, 1, 0])) == nil)
    #expect(try exact.parseReport(Data([0])) == nil)
    let atLeast = ReportLayoutDriver(
      layout: try inputLayout(
        """
        {"report": {"length": {"atLeast": 2}},
          "buttons": [{"control": "South", "byte": 1, "mask": 1}]}
        """
      )
    )
    #expect(try atLeast.parseReport(Data([0, 1, 0]))?.state.pressed == [.south])
  }

  @Test
  func opposingDirectionsCancel() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 1}}, "hat": [{"encoding": "Directions",
        "up": {"byte": 0, "mask": 1}, "right": {"byte": 0, "mask": 2},
        "down": {"byte": 0, "mask": 4}, "left": {"byte": 0, "mask": 8}}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x05]))?.state == .neutral)
    #expect(try driver.parseReport(Data([0x07])).contains(.hat(.east)))
    #expect(layout.controls == Control.dpad)
  }

  @Test
  func aTableHatNamesDirectionsForMaskedValues() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 1}}, "hat": [{"encoding": "Table", "byte": 0, "mask": 240,
        "values": {"1": "North", "9": "NorthEast"}}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x10]))?.state.hat == .north)
    #expect(try driver.parseReport(Data([0x9F]))?.state.hat == .northEast)
    #expect(try driver.parseReport(Data([0x20]))?.state.hat == .neutral)
    #expect(layout.controls == Control.dpad)
  }

  @Test
  func aSymmetricAxisDividesBothSidesByTheMaximum() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 2}},
        "axes": [{"control": "LeftStickX", "byte": 0, "bits": 16,
          "signed": true, "min": -32768, "max": 32767, "symmetric": true}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x00, 0x80]))?.state.leftStick.x.normalized == -1)
    #expect(try driver.parseReport(Data([0x01, 0x80]))?.state.leftStick.x.normalized == -1)
    #expect(try driver.parseReport(Data([0xFF, 0x7F]))?.state.leftStick.x.normalized == 1)
    #expect(try driver.parseReport(Data([0x00, 0x00]))?.state.leftStick.x.normalized == 0)
  }

  @Test
  func aSymmetricAxisWithoutRangeUsesTheFullRange() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": {"atLeast": 2}},
        "axes": [{"control": "LeftStickX", "byte": 0, "bits": 16,
          "signed": true, "symmetric": true}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x00, 0x80]))?.state.leftStick.x.normalized == -1)
    #expect(try driver.parseReport(Data([0xFF, 0x7F]))?.state.leftStick.x.normalized == 1)
    #expect(try driver.parseReport(Data([0x00, 0x00]))?.state.leftStick.x.normalized == 0)
  }

  @Test(arguments: invalidSymmetricAxesAndTableHats)
  func rejectsInvalidSymmetricAxesAndTableHats(json: String) {
    #expect(throws: DecodingError.self) { try inputLayout(json) }
  }

  @Test(arguments: invalidLayouts)
  func rejectsInvalidLayouts(json: String) {
    #expect(throws: DecodingError.self) { try inputLayout(json) }
  }
}
