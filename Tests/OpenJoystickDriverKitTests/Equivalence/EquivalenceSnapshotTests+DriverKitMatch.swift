import Foundation
import OpenJoystickDriverTestSupport
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

/// Snapshots the DriverKit match list: the Info.plist personality and entitlements the generator
/// writes for the USB extension, with fixed versions so the text does not move between builds.
struct EquivalenceSnapshotDriverKitMatchTests {
  @Test
  func generatedMatchListMatchesSnapshot() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-equivalence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DriverExtensionGenerator.generate(
      configuration: USBDriverKitExtensionConfiguration.driver,
      options: DriverExtensionGenerationOptions(
        shortVersion: "0.0.0",
        buildVersion: "0",
        deploymentTarget: "21.0"
      ),
      at: directory
    )
    let sections = try ["Info.plist", "SwifterKitRuntime.entitlements"].map { name in
      let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
      return (
        title: name,
        lines: text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(
          String.init
        )
      )
    }
    let rendered = EquivalenceSnapshotStore.render(sections)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "driverkit-match.txt") == nil)
  }
}
