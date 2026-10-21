import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The families whose descriptions hold the input layout: `ReportLayoutDriver` decodes them, and
/// the recorded samples of their former drivers pass through it unchanged
/// (`DriverParseCharacterizationTests`, the per-family driver tests).
struct XboxXIDDescriptionTests {
  private static let described: [PhysicalProtocolID] = [
    .xboxXID, .nintendoSwitchInputOnly, .vendorFlydigi,
  ]

  @Test(arguments: described)
  func descriptionsDeclareTheirLayoutThroughTheInputSection(family: PhysicalProtocolID) {
    let description = family.protocolDescription
    #expect(description.recordSections.contains(.input))
    #expect(description.inputLayout != nil)
    #expect(!family.requiresRecordInputLayout)
  }

  @Test(arguments: described)
  func advertisedControlsAreTheControlsTheLayoutDecodes(family: PhysicalProtocolID) throws {
    let layout = try #require(family.protocolDescription.inputLayout)
    #expect(family.describedControls == ControllerCapabilities(controls: layout.controls))
  }

  @Test
  func xidDeclaresTheTwentyByteReportOfAnyLength() throws {
    let layout = try #require(ProtocolDescription.bundled[.xboxXID]?.inputLayout)
    #expect(layout.reportID == nil)
    #expect(layout.minimumLength == 20)
    #expect(!layout.requiresExactLength)
  }

  @Test
  func switchInputOnlyDeclaresTheSevenByteReportWithoutAnID() throws {
    let layout = try #require(ProtocolDescription.bundled[.nintendoSwitchInputOnly]?.inputLayout)
    #expect(layout.reportID == nil)
    #expect(layout.minimumLength == 7)
    #expect(!layout.requiresExactLength)
  }

  @Test
  func flydigiDeclaresExactlyFifteenBytesWithReportID1() throws {
    let layout = try #require(ProtocolDescription.bundled[.vendorFlydigi]?.inputLayout)
    #expect(layout.reportID == 1)
    #expect(layout.minimumLength == 15)
    #expect(layout.requiresExactLength)
  }
}
