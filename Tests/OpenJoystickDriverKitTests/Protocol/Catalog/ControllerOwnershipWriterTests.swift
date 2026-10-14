import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerOwnershipWriterTests {
  /// A bundled `sony.dualshock4` record, a HID family.
  private static let bundledHID = ControllerIdentity(vendorID: 0x2C22, productID: 0x2000)
  /// A bundled `xbox.gip` record, a raw-USB family.
  private static let bundledGIP = ControllerIdentity(vendorID: 0x366C, productID: 0x0005)
  private static let unbundled = ControllerIdentity(vendorID: 0x1234, productID: 0xABCD)

  private static func directory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-ownership-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test
  func missingFileBecomesAPatchOfOnlyOwnership() throws {
    let directory = try Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let change = try ControllerOwnershipWriter.change(
      Self.bundledHID,
      to: .ojd,
      records: .load(userDirectory: directory),
      directory: directory
    )
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

  @Test
  func existingFileKeepsItsOtherKeys() throws {
    let directory = try Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("2c22-2000.json")
    try JSONSerialization.data(withJSONObject: [
      "$schema": ControllerRecordSet.overrideSchemaID, "operation": "patch", "vendorID": 0x2C22,
      "productID": 0x2000, "set": ["ownership": "ojd", "tuning": ["stickDeadzone": 0.1]],
    ])
    .write(to: file)
    let change = try ControllerOwnershipWriter.change(
      Self.bundledHID,
      to: .macOS,
      records: .load(userDirectory: directory),
      directory: directory
    )
    #expect(!change.created)
    #expect(change.previous == .ojd)
    try ControllerOwnershipWriter.write(change)
    let set = try #require(try Self.object(Data(contentsOf: file))["set"] as? [String: Any])
    #expect(set["ownership"] as? String == "macos")
    #expect(set["tuning"] as? [String: Double] == ["stickDeadzone": 0.1])
  }

  @Test
  func invalidFileIsRefusedAndKept() throws {
    let directory = try Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("2c22-2000.json")
    try Data("{".utf8).write(to: file)
    #expect(throws: ControllerOwnershipWriter.Failure.invalidFile("the file is not a JSON object")) {
      try ControllerOwnershipWriter.change(
        Self.bundledHID,
        to: .ojd,
        records: .load(userDirectory: directory),
        directory: directory
      )
    }
    #expect(try Data(contentsOf: file) == Data("{".utf8))
  }

  @Test
  func modelWithoutABundledRecordIsRefused() throws {
    let directory = try Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(throws: ControllerOwnershipWriter.Failure.noRecord) {
      try ControllerOwnershipWriter.change(
        Self.unbundled,
        to: .ojd,
        records: .load(userDirectory: directory),
        directory: directory
      )
    }
  }

  @Test
  func rawUSBModelIsRefused() throws {
    let directory = try Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
      _ = try ControllerOwnershipWriter.change(
        Self.bundledGIP,
        to: .ojd,
        records: .load(userDirectory: directory),
        directory: directory
      )
      Issue.record("a raw-USB model was accepted")
    } catch {
      guard case .invalidResult(let problem) = error else {
        Issue.record("unexpected failure \(error)")
        return
      }
      #expect(problem.contains("ownership"))
    }
  }

  /// `change` computes the record; only `write` touches the directory, which is how
  /// `--dry-run` writes nothing.
  @Test
  func changeAloneWritesNothing() throws {
    let directory = try Self.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let change = try ControllerOwnershipWriter.change(
      Self.bundledHID,
      to: .ojd,
      records: .load(userDirectory: directory),
      directory: directory
    )
    #expect(!FileManager.default.fileExists(atPath: change.file.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }
}
