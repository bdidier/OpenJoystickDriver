import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The documents that Python's schema tests reject, read from the files that
/// `Tests/RepositoryScripts/test_schema_rejections.py` reads too. The Swift decoders refuse each
/// with the same error code as Python, so a rule that only one side enforces fails here.
struct SchemaRejectionTests {
  private static func cases(_ file: String) throws -> [[String: Any]] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Catalog
      .deletingLastPathComponent()  // Protocol
      .deletingLastPathComponent()  // OpenJoystickDriverKitTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("RepositoryScripts/fixtures/schema_rejections/\(file)")
    let root = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    return try #require(root["cases"] as? [[String: Any]])
  }

  @Test
  func everyControllerRecordPythonRejectsIsRefusedWithTheSameCode() throws {
    let cases = try Self.cases("controller.json")
    #expect(cases.count > 100)
    var failures: [String] = []
    for fixture in cases {
      let name = try #require(fixture["name"] as? String)
      let code = try #require(fixture["code"] as? String)
      let document = try #require(fixture["document"] as? [String: Any])
      do {
        _ = try ControllerRecordSet.makeRecord(document, layers: [:])
        failures.append("\(name): accepted, Python gives \(code)")
      } catch {
        let found = ControllerRecordSet.problemCode(error)?.rawValue
        if found != code {
          let reason = ControllerRecordSet.problemDescription(error)
          failures.append("\(name): \(found ?? "no code") for \(reason); Python gives \(code)")
        }
      }
    }
    #expect(
      failures.isEmpty,
      "\(failures.count) of \(cases.count):\n\(failures.joined(separator: "\n"))"
    )
  }

  @Test
  func everyProtocolDescriptionPythonRejectsIsRefusedWithTheSameCode() throws {
    let cases = try Self.cases("protocol-description.json")
    #expect(cases.count > 100)
    var failures: [String] = []
    for fixture in cases {
      let name = try #require(fixture["name"] as? String)
      let code = try #require(fixture["code"] as? String)
      let fileName = try #require(fixture["fileName"] as? String)
      let document = try #require(fixture["document"] as? [String: Any])
      let data = try JSONSerialization.data(withJSONObject: document)
      do {
        _ = try ProtocolDescription.decode(data, fileName: fileName)
        failures.append("\(name): accepted, Python gives \(code)")
      } catch {
        if error.code.rawValue != code {
          failures.append("\(name): \(error); Python gives \(code)")
        }
      }
    }
    #expect(
      failures.isEmpty,
      "\(failures.count) of \(cases.count):\n\(failures.joined(separator: "\n"))"
    )
  }
}
