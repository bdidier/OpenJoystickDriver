import Foundation
import Testing

@testable import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport

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

  /// What the Swift decoder gives one case: its code and message.
  private static func controllerRefusal(_ document: [String: Any]) -> (code: String?, text: String)?
  {
    do {
      _ = try ControllerRecordSet.makeRecord(document, layers: [:])
      return nil
    } catch {
      return (
        ControllerRecordSet.problemCode(error)?.rawValue,
        ControllerRecordSet.problemDescription(error, document: "record")
      )
    }
  }

  private static func descriptionRefusal(
    _ document: [String: Any],
    fileName: String
  ) throws -> (code: String?, text: String)? {
    let data = try JSONSerialization.data(withJSONObject: document)
    do {
      _ = try ProtocolDescription.decode(data, fileName: fileName)
      return nil
    } catch { return (error.code.rawValue, error.description) }
  }

  /// With `OJD_SCHEMA_REJECTION_MESSAGES` set to a path, the test writes the message of every
  /// case there, for `./Scripts/ojd fixtures regenerate schema-rejections --write`, and leaves
  /// the messages unchecked.
  @Test
  func everyRejectionPythonMakesIsRefusedWithTheSameCodeAndMessage() throws {
    let recordingPath = ProcessInfo.processInfo.environment["OJD_SCHEMA_REJECTION_MESSAGES"]
    var recorded: [String: [String: String]] = [:]
    var failures: [String] = []
    for kind in ["controller", "protocol-description"] {
      let cases = try Self.cases("\(kind).json")
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
          failures.append("\(kind) \(name): accepted, Python gives \(code)")
          continue
        }
        recorded[kind, default: [:]][name] = refusal.text
        if refusal.code != code {
          let found = refusal.code ?? "no code"
          failures.append("\(kind) \(name): \(found) for \(refusal.text); Python gives \(code)")
        } else if recordingPath == nil, refusal.text != fixture["swift"] as? String {
          failures.append("\(kind) \(name): message \(refusal.text)")
        }
      }
    }
    if let recordingPath {
      let data = try JSONSerialization.data(withJSONObject: recorded, options: .sortedKeys)
      try data.write(to: URL(fileURLWithPath: recordingPath))
    }
    #expect(failures.isEmpty, "\(failures.count):\n\(failures.joined(separator: "\n"))")
  }
}
