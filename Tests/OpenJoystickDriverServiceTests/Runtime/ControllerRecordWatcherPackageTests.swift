import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

@MainActor
struct ControllerRecordWatcherPackageTests {
  private static let schema =
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/v1beta1/"

  private static let record = Data(
    """
    {"$schema": "\(ControllerRecordSet.overrideSchemaID)", "operation": "add",
     "record": {"$schema": "\(schema)controller.schema.json", "vendorID": 4660,
     "productID": 43981, "protocol": {"family": "xbox.gip"}}}
    """.utf8
  )

  private static let manifest = Data(
    """
    {"$schema": "\(schema)mod-package.schema.json", "name": "arcade-pack", "version": "1.0.0",
     "author": "Tester", "requires": {"minimum": "0.6.0"}, "records": ["1234-abcd.json"]}
    """.utf8
  )

  @Test
  func appliesAgainWhenAPackageIsInstalledAndRemoved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-watch-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let staged = root.appendingPathComponent("Staging/arcade-pack", isDirectory: true)
    try FileManager.default.createDirectory(
      at: staged.appendingPathComponent("Controllers"),
      withIntermediateDirectories: true
    )
    try Self.manifest.write(to: staged.appendingPathComponent("mod.json"))
    try Self.record.write(to: staged.appendingPathComponent("Controllers/1234-abcd.json"))

    var applied: [Int] = []
    var changes = 0
    let watcher = ControllerRecordWatcher(
      directory: root.appendingPathComponent("Controllers", isDirectory: true),
      activate: { records in
        applied.append(records.userFiles.count)
        return [ControllerIdentity(vendorID: 0x1234, productID: 0xabcd)]
      },
      onChange: { _ in changes += 1 }
    )
    watcher.start()
    defer { watcher.stop() }
    #expect(applied == [0])

    let store = ModPackageStore(
      directory: root.appendingPathComponent("Packages", isDirectory: true),
      runningVersion: "0.6.0"
    )
    try store.install(staged)
    for _ in 0..<50 where changes == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
    #expect(applied.last == 1)
    #expect(changes >= 1)

    let installedChanges = changes
    try store.remove("arcade-pack")
    for _ in 0..<50 where changes == installedChanges {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(applied.last == 0)
    #expect(changes > installedChanges)
  }
}
