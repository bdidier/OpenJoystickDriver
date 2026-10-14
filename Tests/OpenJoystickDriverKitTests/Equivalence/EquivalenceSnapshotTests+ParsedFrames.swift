import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Snapshots the canonical frames every recorded sample report parses to today.
///
/// Only the records with sample reports in this repository appear; the controller records carry
/// none, so the rest of the catalog has no parsed output to snapshot.
struct EquivalenceSnapshotParsedFramesTests {
  typealias Subjects = DriverLifecycleCharacterizationTests
  typealias Parse = DriverParseCharacterizationTests

  private struct Entry {
    let steps: String
    let subject: Subjects.Subject
    let reports: [Parse.Step]
  }

  private static var entries: [Entry] {
    [
      Entry(steps: "gipSteps", subject: Subjects.gipUSB, reports: Parse.gipSteps),
      Entry(steps: "gipSplitSteps", subject: Subjects.gipUSB, reports: Parse.gipSplitSteps),
      Entry(steps: "xusbWiredSteps", subject: Subjects.xusbWired, reports: Parse.xusbWiredSteps),
      Entry(
        steps: "xusbReceiverSteps",
        subject: Subjects.xusbReceiver,
        reports: Parse.xusbReceiverSteps
      ),
      Entry(steps: "xidSteps", subject: Subjects.xidGamepad, reports: Parse.xidSteps),
      Entry(steps: "sixaxisSteps", subject: Subjects.sixaxisUSB, reports: Parse.sixaxisSteps),
      Entry(
        steps: "sixaxisSteps.prefix(4)",
        subject: Subjects.sixaxisBluetooth,
        reports: Array(Parse.sixaxisSteps.prefix(4))
      ),
      Entry(
        steps: "dualShock4USBSteps",
        subject: Subjects.dualShock4USB,
        reports: Parse.dualShock4USBSteps
      ),
      Entry(
        steps: "dualShock4BluetoothSteps",
        subject: Subjects.dualShock4Bluetooth,
        reports: Parse.dualShock4BluetoothSteps
      ),
      Entry(
        steps: "dualSenseUSBSteps",
        subject: Subjects.dualSenseUSB,
        reports: Parse.dualSenseUSBSteps
      ),
      Entry(
        steps: "dualSenseBluetoothSteps",
        subject: Subjects.dualSenseBluetooth,
        reports: Parse.dualSenseBluetoothSteps
      ),
      Entry(steps: "switchSteps", subject: Subjects.switchUSB, reports: Parse.switchSteps),
      Entry(
        steps: "switchSteps.prefix(3)",
        subject: Subjects.switchBluetooth,
        reports: Array(Parse.switchSteps.prefix(3))
      ),
      Entry(steps: "steamSteps", subject: Subjects.steamWired, reports: Parse.steamSteps),
      Entry(steps: "flydigiSteps", subject: Subjects.flydigi, reports: Parse.flydigiSteps),
      Entry(steps: "gameSirUSBSteps", subject: Subjects.gameSirUSB, reports: Parse.gameSirUSBSteps),
      Entry(
        steps: "gameSirEnhancedSteps",
        subject: Subjects.gameSirEnhancedHID,
        reports: Parse.gameSirEnhancedSteps
      ),
      Entry(
        steps: "hidDescriptorSteps",
        subject: Subjects.hidDescriptor,
        reports: Parse.hidDescriptorSteps
      ),
      Entry(
        steps: "capturedDualShock4",
        subject: Subjects.dualShock4USB,
        reports: Parse.capturedSteps(Parse.capturedDualShock4)
      ),
      Entry(
        steps: "capturedSixaxis",
        subject: Subjects.sixaxisUSB,
        reports: Parse.capturedSteps(Parse.capturedSixaxis)
      ),
    ]
  }

  private static func hex(_ value: UInt16) -> String {
    let digits = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: 4 - digits.count) + digits
  }

  @Test
  func parsedFramesMatchSnapshot() throws {
    let parse = Parse()
    var sections: [(title: String, lines: [String])] = []
    for entry in Self.entries {
      let identifier = entry.subject.identifier.controllerIdentity
      let title =
        "\(Self.hex(identifier.vendorID)):\(Self.hex(identifier.productID))"
        + " host=\(entry.subject.host) steps=\(entry.steps)"
      sections.append((title, try parse.transcript(entry.subject, entry.reports)))
    }
    let captured: [(UInt16, UInt16, String, [Parse.Step])] = [
      (0x3537, 0x1010, "capturedG7SEStatus", Parse.gipCapturedSteps(Parse.capturedG7SEStatus)),
      (0x1532, 0x0A15, "capturedRazerStatus", Parse.gipCapturedSteps(Parse.capturedRazerStatus)),
    ]
    for (vendor, product, name, steps) in captured {
      let lines = parse.transcript(
        try Parse.captured(vendor, product),
        labels: .standard,
        steps
      )
      sections.append(("\(Self.hex(vendor)):\(Self.hex(product)) host=usb steps=\(name)", lines))
    }
    let rendered = EquivalenceSnapshotStore.render(sections)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "parsed-frames.txt") == nil)
  }
}
