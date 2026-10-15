import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// One valid button, for cases that vary only another part of the layout.
private let button = #"{"control": "face-south", "byte": 1, "mask": 1}"#

/// Layouts the symmetric axis and table hat rules reject.
private let invalidSymmetricAxesAndTableHats: [String] = [
  #"{"report": {"length": 2}, "#
    + #""axes": [{"control": "left-stick-x", "byte": 1, "symmetric": true}]}"#,
  #"{"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 1, "signed": true, "#
    + #""min": 0, "max": 127, "symmetric": true}]}"#,
  #"{"report": {"length": 2}, "hat": [{"encoding": "table", "byte": 1, "mask": 15, "#
    + #""values": {}}]}"#,
  #"{"report": {"length": 2}, "hat": [{"encoding": "table", "byte": 1, "mask": 15, "#
    + #""values": {"16": "north"}}]}"#,
  #"{"report": {"length": 2}, "hat": [{"encoding": "table", "byte": 1, "mask": 15, "#
    + #""values": {"01": "north"}}]}"#,
  #"{"report": {"length": 2}, "hat": [{"encoding": "table", "byte": 1, "mask": 15, "#
    + #""values": {"1": "neutral"}}]}"#,
  #"{"report": {"length": 2}, "hat": [{"encoding": "table", "byte": 1, "mask": 15, "#
    + #""values": {"1": "up"}}]}"#,
  #"{"report": {"length": 2}, "hat": [{"encoding": "table", "byte": 1, "mask": 15}]}"#,
]

@Suite
struct ControllerInputLayoutTests {
  @Test
  func repeatedButtonFieldsAreAlternatives() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 2}, "buttons": [
        {"control": "face-north", "byte": 0, "mask": 8},
        {"control": "face-north", "byte": 1, "mask": 128}
      ]}
      """
    )
    #expect(layout.buttons.count == 1)
    #expect(
      layout.buttons.first?.fields == [
        ReportBitField(byte: 0, mask: 8), ReportBitField(byte: 1, mask: 128),
      ]
    )
    #expect(layout.controls == [.faceNorth])
  }

  @Test
  func opposingDirectionsCancel() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 1}, "hat": [{"encoding": "directions",
        "up": {"byte": 0, "mask": 1}, "right": {"byte": 0, "mask": 2},
        "down": {"byte": 0, "mask": 4}, "left": {"byte": 0, "mask": 8}}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x05]))?.state == .neutral)
    #expect(try driver.parseReport(Data([0x07])).contains(.hat(.east)))
    #expect(layout.controls == [.dpad])
  }

  @Test
  func aTableHatNamesDirectionsForMaskedValues() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 1}, "hat": [{"encoding": "table", "byte": 0, "mask": 240,
        "values": {"1": "north", "9": "northEast"}}]}
      """
    )
    let driver = ReportLayoutDriver(layout: layout)
    #expect(try driver.parseReport(Data([0x10]))?.state.hat == .north)
    #expect(try driver.parseReport(Data([0x9F]))?.state.hat == .northEast)
    #expect(try driver.parseReport(Data([0x20]))?.state.hat == .neutral)
    #expect(layout.controls == [.dpad])
  }

  @Test
  func aSymmetricAxisDividesBothSidesByTheMaximum() throws {
    let layout = try inputLayout(
      """
      {"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 0, "bits": 16,
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
      {"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 0, "bits": 16,
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

  @Test(
    arguments: [
      // Report bounds.
      #"{"report": {"id": 0, "length": 2}, "buttons": [\#(button)]}"#,
      #"{"report": {"id": 256, "length": 2}, "buttons": [\#(button)]}"#,
      #"{"report": {"length": 0}, "buttons": [\#(button)]}"#,
      #"{"report": {"length": 65}, "buttons": [\#(button)]}"#,
      #"{"report": {"id": 1, "length": 1}, "buttons": [\#(button)]}"#,
      // Fields.
      #"{"report": {"length": 2}, "buttons": [{"control": "face-south", "byte": 1, "mask": 0}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "face-south", "byte": 1, "mask": 256}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "face-south", "byte": 2, "mask": 1}]}"#,
      #"{"report": {"id": 1, "length": 2}, "#
        + #""buttons": [{"control": "face-south", "byte": 0, "mask": 1}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "dpad", "byte": 1, "mask": 1}]}"#,
      #"{"report": {"length": 2}, "buttons": [{"control": "left-trigger", "byte": 1, "mask": 1}]}"#,
      // Hat.
      #"{"report": {"length": 2}, "hat": [{"encoding": "8-way", "byte": 1, "mask": 3}]}"#,
      #"{"report": {"length": 2}, "hat": [{"encoding": "8-way", "byte": 1, "mask": 11}]}"#,
      #"{"report": {"length": 2}, "hat": [{"encoding": "4-way", "byte": 1, "mask": 15}]}"#,
      // Axes.
      #"{"report": {"length": 2}, "axes": [{"control": "face-south", "byte": 1}]}"#,
      #"{"report": {"length": 3}, "axes": [{"control": "left-stick-x", "byte": 1}, "#
        + #"{"control": "left-stick-x", "byte": 2}]}"#,
      #"{"report": {"length": 3}, "axes": [{"control": "left-stick-x", "byte": 1, "bits": 12}]}"#,
      #"{"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 1, "bits": 16}]}"#,
      #"{"report": {"length": 2}, "#
        + #""axes": [{"control": "left-stick-x", "byte": 1, "min": 10, "max": 11}]}"#,
      #"{"report": {"length": 2}, "axes": [{"control": "left-stick-x", "byte": 1, "max": 256}]}"#,
      // Triggers and shape.
      #"{"report": {"length": 2}, "leftTrigger": {}}"#,
      #"{"report": {"length": 2}}"#,
      #"{"report": {"length": 2}, "buttons": []}"#,
      #"{"report": {"length": 2}, "buttons": [\#(button)], "touchpad": {}}"#,
      #"{"report": {"length": 2, "endpoint": 1}, "buttons": [\#(button)]}"#,
    ]
  )
  func rejectsInvalidLayouts(json: String) {
    #expect(throws: DecodingError.self) { try inputLayout(json) }
  }
}
