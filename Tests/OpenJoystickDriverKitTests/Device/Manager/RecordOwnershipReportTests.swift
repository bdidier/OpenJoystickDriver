import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverTestSupport

/// The status reports the record's ownership of each controller, so the app can offer the
/// Native / Virtual choice for a model that OJD serves although macOS supports it.
struct RecordOwnershipReportTests {
  private static let gameSir = ControllerModelID(vendorID: 0x3537, productID: 0x100B)

  /// The value `DeviceManager.deviceDescription` reports comes from the catalog that the
  /// bundled, package, and user layers produce, so a user patch shows as `ojd`.
  @Test
  func theCatalogRecordCarriesTheOwnershipOfTheMergedLayers() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-record-ownership-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(DeviceCatalog().record(for: Self.gameSir)?.ownership == .macOS)
    try JSONSerialization.data(
      withJSONObject: ControllerPatch.document(
        selector: .identity(ControllerModelID(vendorID: 0x3537, productID: 0x100B)),
        body: ["ownership": "ojd"]
      )
    )
    .write(to: directory.appendingPathComponent("3537-100b.patch.json"))

    let records = ControllerRecordSet.load(userDirectory: directory)

    #expect(records.problems.isEmpty)
    #expect(DeviceCatalog(records: records).record(for: Self.gameSir)?.ownership == .ojd)
  }

  @Test
  func theDescriptionEncodesAndDecodesTheRecordOwnership() throws {
    let device = ApplicationServiceDeviceDescription.fixture(id: "A")
    #expect(device.recordOwnership == .macOS)
    let object = try Self.object(of: device)

    #expect(object["recordOwnership"] as? String == "macos")
    var owned = object
    owned["recordOwnership"] = "ojd"
    #expect(try Self.decoded(owned).recordOwnership == .ojd)
  }

  /// A service that predates the field sends none, and the app then treats the record as native.
  @Test
  func aPayloadWithoutTheFieldDecodesAsMacOS() throws {
    var object = try Self.object(of: .fixture(id: "A"))
    object["recordOwnership"] = nil

    #expect(try Self.decoded(object).recordOwnership == .macOS)
  }

  private static func object(of device: ApplicationServiceDeviceDescription) throws -> [String: Any]
  {
    let data = try JSONEncoder().encode(device)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private static func decoded(_ object: [String: Any]) throws -> ApplicationServiceDeviceDescription
  {
    try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }
}
