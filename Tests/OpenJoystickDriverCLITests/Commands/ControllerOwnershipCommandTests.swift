import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ControllerOwnershipCommandTests {
  /// A user record directory for one test, beside an empty `Packages` store.
  private final class Directory {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-ownership-\(UUID().uuidString)",
      isDirectory: true
    )

    var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
    var file: URL { controllers.appendingPathComponent("2c22-2000.json") }

    deinit { try? FileManager.default.removeItem(at: root) }
  }

  /// A connected `sony.dualshock4` model, a HID family; `native` makes macOS serve it.
  private static func device(
    vendorID: UInt16 = 0x2C22,
    productID: UInt16 = 0x2000,
    native: Bool
  ) throws -> ApplicationServiceDeviceDescription {
    let fixture = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      vendorID: vendorID,
      productID: productID
    )
    guard native else { return fixture }
    var object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as? [String: Any]
    )
    object["physicalOwnership"] = ControllerOwnershipObservation.nativeGamepad.rawValue
    return try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private static func run(
    _ arguments: [String],
    device: ApplicationServiceDeviceDescription,
    in directory: Directory
  ) async throws -> CLIRun {
    let service = try FakeService(devices: [device])
    return await RecordStore.$directory.withValue(directory.controllers) {
      await service.run(arguments)
    }
  }

  private static func ownership(in directory: Directory) -> ControllerServer? {
    ControllerRecordSet.load(userDirectory: directory.controllers)
      .records[ControllerModelID(vendorID: 0x2C22, productID: 0x2000)]?.server
  }

  @Test
  func virtualWritesTheUserRecord() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual", "--json"],
      device: Self.device(native: true),
      in: directory
    )
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "ControllerOwnership")
    #expect(json["identity"] as? String == "2C22:2000")
    #expect(json["ownership"] as? String == "virtual")
    #expect(json["previous"] as? String == "native")
    #expect(json["created"] as? Bool == true)
    #expect(json["dryRun"] as? Bool == false)
    #expect(json["file"] as? String == directory.file.path)
    #expect(Self.ownership(in: directory) == .ojd)
  }

  @Test
  func nativeSwitchesAVirtualModelBack() async throws {
    let directory = Directory()
    let device = try Self.device(native: false)
    _ = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual"],
      device: Self.device(native: true),
      in: directory
    )
    // OJD seized the controller, so it no longer reports as a native gamepad.
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "native", "--plain"],
      device: device,
      in: directory
    )
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput == "2C22:2000\tnative\t\(directory.file.path)\n")
    #expect(Self.ownership(in: directory) == .system)
  }

  @Test
  func dryRunWritesNothing() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual", "--dry-run", "--json"],
      device: Self.device(native: true),
      in: directory
    )
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["dryRun"] as? Bool == true)
    #expect(!FileManager.default.fileExists(atPath: directory.file.path))
  }

  @Test
  func rawUSBControllerIsRefused() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "native"],
      device: Self.device(vendorID: 0x366C, productID: 0x0005, native: true),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.ownershipToggleUnsupported.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func controllerMacOSDoesNotServeIsRefused() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual"],
      device: Self.device(native: false),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.ownershipToggleUnsupported.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func modelWithoutARecordIsRefused() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual"],
      device: Self.device(vendorID: 0x1234, productID: 0xABCD, native: true),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.ownershipToggleUnsupported.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func showReportsTheChoiceAndItsSource() async throws {
    let directory = Directory()
    let device = try Self.device(native: true)
    let before = try await Self.run(
      ["controller", "show", token("pad-1"), "--json"],
      device: device,
      in: directory
    )
    let beforeOwnership = try #require(try before.json()["ownership"] as? [String: Any])
    #expect(beforeOwnership["choice"] as? String == "native")
    #expect(beforeOwnership["choiceSource"] as? String == "default")

    _ = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual"],
      device: device,
      in: directory
    )
    let after = try await Self.run(
      ["controller", "show", token("pad-1"), "--json"],
      device: device,
      in: directory
    )
    let afterOwnership = try #require(try after.json()["ownership"] as? [String: Any])
    #expect(afterOwnership["choice"] as? String == "virtual")
    #expect(afterOwnership["choiceSource"] as? String == "user")

    let plain = try await Self.run(
      ["controller", "show", token("pad-1"), "--plain"],
      device: device,
      in: directory
    )
    #expect(plain.standardOutput.contains("ownership-choice\tvirtual\tuser\n"))
  }
}
