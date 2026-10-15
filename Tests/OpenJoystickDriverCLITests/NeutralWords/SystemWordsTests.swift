import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Task 17.1 part C: the words `bundle`, `macOS` and `apple` left the command line and the support
/// report. Each old word is refused, and the refusal names the new word.
struct SystemWordsTests {
  @Test
  func theOldDiagnoseBundleFlagIsRefusedAndNamesOutput() async {
    let path = "/tmp/\(UUID().uuidString)-support.json"

    for arguments in [
      ["diagnose", "--bundle", path],
      ["diagnose", "--bundle=\(path)"],
      ["--json", "diagnose", "--bundle", path],
    ] {
      let result = await CLIRun.run(arguments)

      #expect(result.code == 64, "\(arguments)")
      #expect(result.standardOutput.isEmpty, "\(arguments)")
      #expect(result.standardError.hasPrefix("error[E"), "\(arguments)")
      #expect(result.standardError.contains("'--bundle' was renamed to '--output'"), "\(arguments)")
      #expect(!FileManager.default.fileExists(atPath: path), "\(arguments)")
    }
  }

  @Test
  func theNewDiagnoseOutputFlagIsNotRefused() async {
    let result = await CLIRun.run(["diagnose", "--help"])

    #expect(result.code == 0)
    #expect(result.standardOutput.contains("--output"))
    #expect(!result.standardOutput.contains("--bundle"))
  }

  struct Rename {
    /// The object that holds the field, as keys from the document root.
    let container: [String]
    let old: String
    let new: String
    /// Whether the schema requires the new field, so that its absence names it too.
    let required: Bool
  }

  static let renames = [
    Rename(
      container: ["data", "system"],
      old: "macOSVersion",
      new: "osVersion",
      required: true
    ),
    Rename(
      container: ["data"],
      old: "appleGameControllerAudit",
      new: "systemGamepadAudit",
      required: false
    ),
    Rename(
      container: ["data", "systemGamepadAudit"],
      old: "appleExactDeviceCount",
      new: "systemExactDeviceCount",
      required: true
    ),
    Rename(
      container: ["data", "systemGamepadAudit"],
      old: "skippedAppleDeviceCount",
      new: "skippedSystemDeviceCount",
      required: true
    ),
    Rename(
      container: ["data", "systemGamepadAudit", "records", "0"],
      old: "appleIdentifiers",
      new: "systemIdentifiers",
      required: true
    ),
  ]

  private func reportDocument() throws -> [String: Any] {
    let audit = SystemGamepadSupportAuditor.audit(
      snapshot: SystemGamepadCatalogSnapshot(
        source: .downloadedMobileAsset,
        bundleVersions: ["10.5.2"],
        entries: [
          SystemGamepadCatalogEntry(vendorID: 1_234, productID: 5_678, identifiers: ["a.b"])
        ]
      ),
      records: [ControllerModelID(vendorID: 1_234, productID: 5_678)]
    )
    let report = SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      buildIdentity: BuildIdentity(
        semanticVersion: "0.5.0-beta.4",
        appBundleVersion: "1.4.89",
        sourceCommit: String(repeating: "a", count: 40),
        sourceState: .clean
      ),
      osName: "macOS",
      osVersion: "26.0.0",
      architecture: "arm64",
      inputMonitoring: .granted,
      applicationServiceInstalled: true,
      applicationServiceConnected: true,
      applicationServiceHealth: nil,
      systemGamepadAudit: audit,
      status: nil,
      virtualDiagnostics: nil
    )
    let object = try JSONSerialization.jsonObject(with: report.encodedJSON())
    return try #require(object as? [String: Any])
  }

  private func issues(
    in document: [String: Any],
    against reference: String = "report.schema.json"
  ) throws -> [String] {
    try JSONSchemaFiles.Validator().validate(
      document,
      against: ["$ref": reference],
      in: String(reference.prefix { $0 != "#" }),
      at: "$"
    )
  }

  /// Renames `old` to `new` or the reverse inside the object at `path`.
  private func rename(
    _ value: Any,
    at path: ArraySlice<String>,
    from: String,
    to: String
  ) -> Any {
    if let key = path.first {
      if var object = value as? [String: Any], let child = object[key] {
        object[key] = rename(child, at: path.dropFirst(), from: from, to: to)
        return object
      }
      if var array = value as? [Any], let index = Int(key), array.indices.contains(index) {
        array[index] = rename(array[index], at: path.dropFirst(), from: from, to: to)
        return array
      }
      return value
    }
    guard var object = value as? [String: Any], let moved = object.removeValue(forKey: from)
    else { return value }
    object[to] = moved
    return object
  }

  @Test
  func theReportThatUsesTheNewWordsPassesTheSchema() throws {
    let document = try reportDocument()

    #expect(try issues(in: document).isEmpty)
    let system = try #require((document["data"] as? [String: Any])?["system"] as? [String: Any])
    #expect(system["osName"] as? String == "macOS")
    #expect(system["osVersion"] as? String == "26.0.0")
  }

  @Test(arguments: Self.renames.indices)
  func aReportWithTheOldWordIsRefused(index: Int) throws {
    let rename = Self.renames[index]
    let changed =
      try #require(
        self.rename(
          try reportDocument(),
          at: rename.container[...],
          from: rename.new,
          to: rename.old
        ) as? [String: Any]
      )

    let found = try issues(in: changed)

    #expect(!found.isEmpty, "\(rename.old) was accepted")
    #expect(found.contains { $0.contains(rename.old) }, "\(found)")
    #expect(
      found.contains { $0.contains("\(rename.old) was renamed to \(rename.new)") },
      "\(found)"
    )
    if rename.required {
      #expect(found.contains { $0.contains("missing \(rename.new)") }, "\(found)")
    }
  }

  @Test
  func theOldDiagnoseJSONFieldIsRefusedAndNamesOutput() throws {
    let document: [String: Any] = [
      "apiVersion": "openjoystickdriver/v1alpha1", "kind": "Diagnosis", "checks": [],
      "timings": [], "output": "/tmp/support.json",
    ]
    #expect(try issues(in: document, against: "cli-output.schema.json#/$defs/diagnose").isEmpty)

    var old = document
    old["bundle"] = old.removeValue(forKey: "output")
    let found = try issues(in: old, against: "cli-output.schema.json#/$defs/diagnose")

    #expect(found.contains { $0.contains("bundle was renamed to output") }, "\(found)")
  }

  @Test
  func everyRenamedFlagRowIsRefusedWithItsNewWord() {
    for rename in RenamedWords.renames {
      guard case .flag(let command) = rename.kind else { continue }
      let match = RenamedWords.match(arguments: [command, rename.old])
      #expect(match?.new == rename.new, "\(rename.old)")
    }
  }
}
