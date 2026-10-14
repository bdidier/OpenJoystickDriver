import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct ControllerOwnershipRequestsTests {
  /// A bundled `sony.dualshock4` record, a HID family.
  private static let bundledHID = (vendorID: 0x2C22, productID: 0x2000)
  /// A bundled `xbox.gip` record, a raw-USB family.
  private static let bundledGIP = (vendorID: 0x366C, productID: 0x0005)

  /// Runs `body` with the `Controllers` folder of a temporary application-support folder, whose
  /// `Packages` store is empty.
  private static func withDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ControllerOwnershipRequestsTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("Controllers", isDirectory: true))
  }

  private static func set(
    _ model: (vendorID: Int, productID: Int),
    to ownership: ControllerOwnership,
    native: Bool,
    in directory: URL
  ) -> ControllerOwnershipResult {
    ApplicationServiceServer.setControllerOwnership(
      vendorID: model.vendorID,
      productID: model.productID,
      ownership: ownership,
      nativeGamepadConnected: native,
      directory: directory
    )
  }

  private static func loadedOwnership(in directory: URL) -> ControllerOwnership? {
    ControllerRecordSet.load(userDirectory: directory)
      .records[ControllerModelID(vendorID: 0x2C22, productID: 0x2000)]?.ownership
  }

  @Test
  func nativeModelIsWrittenAndSwitchedBack() throws {
    try Self.withDirectory { directory in
      let toOJD = Self.set(Self.bundledHID, to: .ojd, native: true, in: directory)
      #expect(toOJD.failure == nil)
      #expect(toOJD.previous == .macOS)
      #expect(toOJD.created)
      #expect(toOJD.file?.hasSuffix("Controllers/2c22-2000.json") == true)
      #expect(Self.loadedOwnership(in: directory) == .ojd)

      // A model OJD already serves counts as native, as its seized controller is no gamepad.
      let back = Self.set(Self.bundledHID, to: .macOS, native: false, in: directory)
      #expect(back.failure == nil)
      #expect(back.previous == .ojd)
      #expect(!back.created)
      #expect(Self.loadedOwnership(in: directory) == .macOS)
    }
  }

  @Test
  func rawUSBModelIsRefusedAndNothingIsWritten() throws {
    try Self.withDirectory { directory in
      let result = Self.set(Self.bundledGIP, to: .macOS, native: true, in: directory)
      #expect(result.failure == .rawUSB)
      #expect(result.file == nil)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func modelMacOSDoesNotServeIsRefused() throws {
    try Self.withDirectory { directory in
      let result = Self.set(Self.bundledHID, to: .ojd, native: false, in: directory)
      #expect(result.failure == .notNative)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func modelWithoutARecordIsRefused() throws {
    try Self.withDirectory { directory in
      let result = Self.set((0x1234, 0xABCD), to: .ojd, native: true, in: directory)
      #expect(result.failure == .noRecord)
      #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
  }

  @Test
  func invalidUserRecordIsRefusedAndKept() throws {
    try Self.withDirectory { directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("2c22-2000.json")
      let bytes = Data("{\"operation\": \"patch\"}".utf8)
      try bytes.write(to: file)
      let result = Self.set(Self.bundledHID, to: .ojd, native: true, in: directory)
      #expect(result.failure == .invalidRecord)
      #expect(result.detail != nil)
      #expect(try Data(contentsOf: file) == bytes)
    }
  }

  @Test
  func resultRoundTripsThroughJSON() throws {
    let result = ControllerOwnershipResult(
      ownership: .ojd,
      previous: .macOS,
      file: "/tmp/2c22-2000.json",
      created: true,
      failure: nil
    )
    let data = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(ControllerOwnershipResult.self, from: data) == result)
    let arguments = try JSONEncoder().encode(
      LocalServiceRPCControllerOwnershipArguments(vendorID: 1, productID: 2, ownership: .macOS)
    )
    let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any]
    #expect(object?["ownership"] as? String == "macos")
  }
}
