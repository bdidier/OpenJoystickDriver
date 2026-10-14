import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ModPackageLayeringTests {
  private typealias Fixture = ModPackageFixture

  private static let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  /// Installs the package by copying it, so the test does not depend on the version check.
  private func install(_ folder: URL, in fixture: Fixture) throws {
    try fixture.store().install(folder, replace: true)
  }

  @Test
  func aPackageRecordLayersBetweenBundledAndUser() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      try install(try fixture.makePackage(records: [record]), in: fixture)

      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      let loaded = try #require(set.records[Self.identity])
      #expect(loaded.layer == .package)
      #expect(loaded.fieldLayers == ["protocol": .package])
      #expect(loaded.file?.lastPathComponent == record.name)
      #expect(set.records.count == ControllerRecordSet.bundled.records.count + 1)
      #expect(set.problems.isEmpty)
      #expect(set.userFiles.map(\.url.lastPathComponent) == [record.name])

      try fixture.store().remove("arcade-pack")
      let removed = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(removed.records[Self.identity] == nil)

      try fixture.write([record], kind: "Controllers", in: fixture.root)
      let user = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(user.records[Self.identity]?.layer == .user)
    }
  }

  @Test
  func aUserRecordBeatsAPackageRecordAndTheLoserIsListed() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      try install(try fixture.makePackage(records: [record]), in: fixture)
      try fixture.write([record], kind: "Controllers", in: fixture.root)

      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.records[Self.identity]?.layer == .user)
      let skipped = try #require(set.problems.first)
      #expect(set.problems.count == 1)
      #expect(skipped.url.path.contains("Packages/arcade-pack/Controllers"))
      #expect(skipped.problem == "replaced by your file \(record.name)")
    }
  }

  @Test
  func amongPackagesTheFirstByNameWinsAndTheLoserIsListed() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      // Packages may not clash when installed, so a clash made by hand stands for one that
      // appeared later, such as a package copied into the store.
      try FileManager.default.createDirectory(
        at: fixture.packages,
        withIntermediateDirectories: true
      )
      for name in ["beta-pack", "alpha-pack"] {
        let folder = try fixture.makePackage(name, records: [record])
        let target = fixture.packages.appendingPathComponent(name)
        try FileManager.default.copyItem(at: folder, to: target)
      }
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.records[Self.identity]?.file?.path.contains("alpha-pack") == true)
      let skipped = try #require(set.problems.first)
      #expect(set.problems.count == 1)
      #expect(skipped.url.path.contains("beta-pack"))
      #expect(skipped.problem == "same controller as package alpha-pack")
    }
  }

  @Test
  func aPackageWithAnInvalidManifestIsListedAndAppliesNothing() throws {
    try Fixture.with { fixture in
      let broken = fixture.packages.appendingPathComponent("broken-pack", isDirectory: true)
      try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
      try Data("{}".utf8).write(to: broken.appendingPathComponent("mod.json"))
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.records.count == ControllerRecordSet.bundled.records.count)
      #expect(set.problems.map(\.url.lastPathComponent) == ["mod.json"])
      #expect(set.problems.first?.problem?.hasPrefix("E4001") == true)
    }
  }

  @Test
  func aPackagePersonaLayersUnderTheUserPersona() throws {
    try Fixture.with { fixture in
      let fromPackage = Fixture.persona(0x1234, 0xABCD, descriptor: "hid-generic")
      try install(try fixture.makePackage(personas: [fromPackage]), in: fixture)
      let store = VirtualHIDProfileOverrideStore(directory: fixture.personas)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .generic)
      #expect(store.problems.isEmpty)

      let user = Fixture.persona(0x1234, 0xABCD, descriptor: "hid-xbox-one-s-bt")
      try fixture.write([user], kind: "Personas", in: fixture.root)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .xboxOneSBluetooth)
      let skipped = try #require(store.problems.first)
      #expect(store.problems.count == 1)
      #expect(skipped.url.path.contains("Packages/arcade-pack/Personas"))
      #expect(skipped.problem == "same match as user file \(user.name)")
    }
  }

  @Test
  func amongPackagesTheFirstPersonaByNameWins() throws {
    try Fixture.with { fixture in
      try FileManager.default.createDirectory(
        at: fixture.packages,
        withIntermediateDirectories: true
      )
      let descriptors = [("beta-pack", "hid-xbox-one-s-bt"), ("alpha-pack", "hid-generic")]
      for (name, descriptor) in descriptors {
        let folder = try fixture.makePackage(
          name,
          personas: [Fixture.persona(0x1234, 0xABCD, descriptor: descriptor)]
        )
        let target = fixture.packages.appendingPathComponent(name)
        try FileManager.default.copyItem(at: folder, to: target)
      }
      let store = VirtualHIDProfileOverrideStore(directory: fixture.personas)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .generic)
      let skipped = try #require(store.problems.first)
      #expect(store.problems.count == 1)
      #expect(skipped.url.path.contains("beta-pack"))
      #expect(skipped.problem == "same match as package file 1234-abcd.json")
    }
  }

  @Test
  func settingAPackagePersonaWritesAUserFileAndLeavesThePackageFile() throws {
    try Fixture.with { fixture in
      let fromPackage = Fixture.persona(0x1234, 0xABCD, descriptor: "hid-generic")
      try install(try fixture.makePackage(personas: [fromPackage]), in: fixture)
      let store = VirtualHIDProfileOverrideStore(directory: fixture.personas)
      try store.set(.xboxOneSBluetooth, vendorID: 0x1234, productID: 0xABCD)
      let written = fixture.personas.appendingPathComponent(fromPackage.name)
      #expect(FileManager.default.fileExists(atPath: written.path))
      let packaged = fixture.packages.appendingPathComponent(
        "arcade-pack/Personas/\(fromPackage.name)"
      )
      #expect(try Data(contentsOf: packaged) == fromPackage.data)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .xboxOneSBluetooth)

      try store.reset(vendorID: 0x1234, productID: 0xABCD)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .generic)
      store.resetAll()
      #expect(FileManager.default.fileExists(atPath: packaged.path))
    }
  }
}
