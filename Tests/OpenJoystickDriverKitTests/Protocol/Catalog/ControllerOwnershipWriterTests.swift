import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerOwnershipWriterTests {
  /// A bundled `sony.dualshock4` record, a HID family.
  private static let bundledHID = ControllerIdentity(vendorID: 0x2C22, productID: 0x2000)
  /// A bundled `xbox.gip` record, a raw-USB family.
  private static let bundledGIP = ControllerIdentity(vendorID: 0x366C, productID: 0x0005)
  private static let unbundled = ControllerIdentity(vendorID: 0x1234, productID: 0xABCD)

  /// Runs `body` with the `Controllers` folder of a temporary application-support folder, whose
  /// `Packages` store is empty unless the test installs a package.
  private static func withDirectory(_ body: (URL, ModPackageFixture) throws -> Void) throws {
    try ModPackageFixture.with { fixture in
      try FileManager.default.createDirectory(
        at: fixture.controllers,
        withIntermediateDirectories: true
      )
      try body(fixture.controllers, fixture)
    }
  }

  private static func change(
    _ identity: ControllerIdentity,
    to ownership: ControllerOwnership,
    in directory: URL
  ) throws -> ControllerOwnershipWriter.Change {
    try ControllerOwnershipWriter.change(
      identity,
      to: ownership,
      records: .load(userDirectory: directory),
      directory: directory
    )
  }

  private static func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test
  func missingFileBecomesAPatchOfOnlyOwnership() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(Self.bundledHID, to: .ojd, in: directory)
      #expect(change.created)
      #expect(change.previous == .macOS)
      #expect(change.file.lastPathComponent == "2c22-2000.json")
      try ControllerOwnershipWriter.write(change)
      let written = try Self.object(Data(contentsOf: change.file))
      #expect(written["operation"] as? String == "patch")
      #expect(written["vendorID"] as? Int == 0x2C22)
      #expect(written["productID"] as? Int == 0x2000)
      #expect(written["set"] as? [String: String] == ["ownership": "ojd"])
      let loaded = ControllerRecordSet.load(userDirectory: directory)
      #expect(loaded.records[Self.bundledHID]?.profile.ownership == .ojd)
      #expect(loaded.records[Self.bundledHID]?.fieldLayers["ownership"] == .user)
    }
  }

  @Test
  func existingFileKeepsItsOtherKeys() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.json")
      try JSONSerialization.data(withJSONObject: [
        "$schema": ControllerRecordSet.overrideSchemaID, "operation": "patch",
        "vendorID": 0x2C22, "productID": 0x2000,
        "set": ["ownership": "ojd", "tuning": ["stickDeadzone": 0.1]],
      ])
      .write(to: file)
      let change = try Self.change(Self.bundledHID, to: .macOS, in: directory)
      #expect(!change.created)
      #expect(change.previous == .ojd)
      try ControllerOwnershipWriter.write(change)
      let set = try #require(try Self.object(Data(contentsOf: file))["set"] as? [String: Any])
      #expect(set["ownership"] as? String == "macos")
      #expect(set["tuning"] as? [String: Double] == ["stickDeadzone": 0.1])
    }
  }

  /// A model that only an installed package has gets a patch over the package record, which
  /// keeps the package's other fields.
  @Test
  func packageOnlyModelGetsAPatchOverThePackageRecord() throws {
    try Self.withDirectory { directory, fixture in
      let record: [String: Any] = [
        "$schema": ControllerRecordSet.overrideSchemaID, "operation": "add",
        "record": [
          "$schema": ControllerRecordDocument.schemaID, "vendorID": 0x1234,
          "productID": 0xABCD, "protocol": ["family": "hid.descriptor"],
        ],
      ]
      let package = try fixture.makePackage(
        records: [("1234-abcd.json", try JSONSerialization.data(withJSONObject: record))]
      )
      try fixture.store().install(package, replace: true)
      let change = try Self.change(Self.unbundled, to: .ojd, in: directory)
      #expect(change.created)
      try ControllerOwnershipWriter.write(change)
      let loaded = ControllerRecordSet.load(userDirectory: directory)
      let effective = try #require(loaded.records[Self.unbundled])
      #expect(effective.profile.ownership == .ojd)
      #expect(effective.fieldLayers == ["protocol": .package, "ownership": .user])
      #expect(loaded.problems.isEmpty)
    }
  }

  @Test
  func invalidFileIsRefusedAndKept() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.json")
      try Data("{".utf8).write(to: file)
      #expect(
        throws: ControllerOwnershipWriter.Failure.invalidFile("the file is not a JSON object")
      ) { try Self.change(Self.bundledHID, to: .ojd, in: directory) }
      #expect(try Data(contentsOf: file) == Data("{".utf8))
    }
  }

  @Test
  func modelWithoutARecordIsRefused() throws {
    try Self.withDirectory { directory, _ in
      #expect(throws: ControllerOwnershipWriter.Failure.noRecord) {
        try Self.change(Self.unbundled, to: .ojd, in: directory)
      }
    }
  }

  @Test
  func rawUSBModelIsRefused() throws {
    try Self.withDirectory { directory, _ in
      do {
        _ = try Self.change(Self.bundledGIP, to: .ojd, in: directory)
        Issue.record("a raw-USB model was accepted")
      } catch {
        guard case .invalidResult(let problem) = error as? ControllerOwnershipWriter.Failure
        else {
          Issue.record("unexpected failure \(error)")
          return
        }
        #expect(problem.contains("ownership"))
      }
    }
  }

  /// `change` computes the record; only `write` touches the directory, which is how
  /// `--dry-run` writes nothing.
  @Test
  func changeAloneWritesNothing() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(Self.bundledHID, to: .ojd, in: directory)
      #expect(!FileManager.default.fileExists(atPath: change.file.path))
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }
}
