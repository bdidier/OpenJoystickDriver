import Foundation
import Testing

@testable import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport

/// The documents the Swift decoders refuse, read from `SchemaRejections/controller.json` and
/// `protocol-description.json`. Each case names the error code its decoder gives. A case with
/// `schema: true` is also rejected by the JSON Schema alone, which
/// `Tests/RepositoryScripts/test_schema_rejection_flags.py` checks.
struct SchemaRejectionTests {
  private static func cases(_ file: String) throws -> [[String: Any]] {
    let url = try #require(
      Bundle.module.url(
        forResource: file,
        withExtension: "json",
        subdirectory: "SchemaRejections"
      )
    )
    let root = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    return try #require(root["cases"] as? [[String: Any]])
  }

  /// The code the Swift decoder gives one case.
  private static func controllerRefusal(_ document: [String: Any]) -> String?? {
    do {
      _ = try ControllerRecordSet.makeRecord(document, order: nil, layers: [:])
      return .none
    } catch {
      return .some(ControllerRecordSet.problemCode(error)?.rawValue)
    }
  }

  private static func descriptionRefusal(
    _ document: [String: Any],
    fileName: String
  ) throws -> String?? {
    let data = try JSONSerialization.data(withJSONObject: document)
    do {
      _ = try ProtocolDescription.decode(data, fileName: fileName)
      return .none
    } catch { return .some(error.code.rawValue) }
  }

  @Test
  func everyListedDocumentIsRefusedWithItsCode() throws {
    var failures: [String] = []
    for kind in ["controller", "protocol-description"] {
      let cases = try Self.cases(kind)
      #expect(cases.count > 100)
      for fixture in cases {
        let name = try #require(fixture["name"] as? String)
        let code = try #require(fixture["code"] as? String)
        let document = try #require(fixture["document"] as? [String: Any])
        let refusal =
          kind == "controller"
          ? Self.controllerRefusal(document)
          : try Self.descriptionRefusal(
            document,
            fileName: try #require(fixture["fileName"] as? String)
          )
        guard let refusal else {
          failures.append("\(kind) \(name): accepted, expected \(code)")
          continue
        }
        if refusal != code {
          failures.append("\(kind) \(name): \(refusal ?? "no code"), expected \(code)")
        }
      }
    }
    #expect(failures.isEmpty, "\(failures.count):\n\(failures.joined(separator: "\n"))")
  }
}
