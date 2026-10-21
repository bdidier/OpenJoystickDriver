import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The shared `ControllerPatch` cases. `Tests/RepositoryScripts/test_controller_patch.py` reads the
/// same file and checks the Python generator against it, so both implementations give the same
/// effective records.
struct ControllerPatchMergeTests {
  private static let cases = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Catalog
    .deletingLastPathComponent()  // Protocol
    .deletingLastPathComponent()  // OpenJoystickDriverKitTests
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("RepositoryScripts/fixtures/controller_patch/cases.json")

  private static func fixture() throws -> [String: Any] {
    try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: cases)) as? [String: Any]
    )
  }

  /// The patches of one layer. An item is a patch document, or `{"owner", "document"}` to name
  /// the package that holds it.
  private static func entries(
    _ value: Any?,
    file: String
  ) throws -> [(patch: ControllerPatch, owner: String?)] {
    try (value as? [[String: Any]] ?? []).map { item in
      let owner = item["owner"] as? String
      let document = item["document"] as? [String: Any] ?? item
      return (try ControllerPatch.parse(document, file: file), owner)
    }
  }

  @Test
  func everyCaseGivesItsEffectiveRecord() throws {
    let cases = try #require(try Self.fixture()["cases"] as? [[String: Any]])
    #expect(cases.count >= 10)
    for fixture in cases {
      let name = try #require(fixture["name"] as? String)
      let record = try #require(fixture["record"] as? [String: Any])
      let expected = try #require(fixture["expected"] as? [String: Any])
      let effective = ControllerPatchMerge.effective(
        record: record,
        builtin: try Self.entries(fixture["builtin"], file: name).map(\.patch),
        package: try Self.entries(fixture["package"], file: name),
        user: try Self.entries(fixture["user"], file: name).map(\.patch)
      )
      // swiftlint:disable:next legacy_objc_type
      #expect(NSDictionary(dictionary: effective).isEqual(to: expected), "\(name)")
    }
  }

  @Test
  func rejectedDocumentsAreRefused() throws {
    let rejected = try #require(try Self.fixture()["rejected"] as? [[String: Any]])
    #expect(!rejected.isEmpty)
    for fixture in rejected {
      let name = try #require(fixture["name"] as? String)
      let document = try #require(fixture["document"] as? [String: Any])
      do {
        _ = try ControllerPatch.parse(document)
        Issue.record("\(name) was accepted")
      } catch {
        let code = ControllerRecordSet.problemCode(error)?.rawValue
        #expect(code == fixture["code"] as? String, "\(name)")
        #expect(
          ControllerRecordSet.problemDescription(error, document: "record") == fixture["message"]
            as? String,
          "\(name)"
        )
      }
    }
  }

  @Test
  func theCasesCoverTheRequiredBehaviour() throws {
    let cases = try #require(try Self.fixture()["cases"] as? [[String: Any]])
    let names = Set(cases.compactMap { $0["name"] as? String })
    #expect(names.contains("null deletes a parameter"))
    #expect(names.contains("a user patch beats a package patch"))
  }

  @Test
  func selectorsOrderAllThenIdentityThenModel() {
    let identity = ControllerModelID(vendorID: 0x045E, productID: 0x02EA)
    let patches = [
      try? ControllerPatch(selector: .identity(identity), body: ["ownership": "ojd"]),
      try? ControllerPatch(selector: .all, body: ["tuning": [:]]),
      try? ControllerPatch(selector: .model("045e-02ea"), body: ["ownership": "macos"]),
    ].compactMap { $0 }
    #expect(ControllerPatchMerge.ordered(patches).map(\.selector.rank) == [0, 1, 2])
  }
}
