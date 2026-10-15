import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverKit

/// The OS-neutral words of the command line and the support report.
struct SystemWordsTests {
  @Test
  func theNewDiagnoseOutputFlagIsNotRefused() async {
    let result = await CLIRun.run(["diagnose", "--help"])

    #expect(result.code == 0)
    #expect(result.standardOutput.contains("--output"))
    #expect(!result.standardOutput.contains("--bundle"))
  }

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
      inputRead: .granted,
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

  @Test
  func theReportThatUsesTheNewWordsPassesTheSchema() throws {
    let document = try reportDocument()

    #expect(try issues(in: document).isEmpty)
    let system = try #require((document["data"] as? [String: Any])?["system"] as? [String: Any])
    #expect(system["osName"] as? String == "macOS")
    #expect(system["osVersion"] as? String == "26.0.0")
  }

  @Test
  func theDiagnoseDocumentWithOutputPassesTheSchema() throws {
    let document: [String: Any] = [
      "apiVersion": "openjoystickdriver/v1alpha1", "kind": "Diagnosis", "checks": [],
      "timings": [], "output": "/tmp/support.json",
    ]

    #expect(try issues(in: document, against: "cli-output.schema.json#/$defs/diagnose").isEmpty)
  }

  @Test
  func aFlagThatEarlierReleasesHadFailsLikeAnyUnknownFlag() async {
    let unknown = "--x\(UUID().uuidString.prefix(8).lowercased())"
    let earlier = await CLIRun.run(["diagnose", "--bundle", "/tmp/support.json"])
    let other = await CLIRun.run(["diagnose", unknown, "/tmp/support.json"])

    #expect(earlier.code != 0)
    #expect(earlier.code == other.code)
    #expect(earlier.standardOutput == other.standardOutput)
    #expect(
      earlier.standardError.replacingOccurrences(of: "--bundle", with: "<flag>")
        == other.standardError.replacingOccurrences(of: unknown, with: "<flag>")
    )
  }

  @Test
  func aFieldThatEarlierReleasesHadFailsLikeAnyUnknownField() throws {
    let unknown = "x\(UUID().uuidString.prefix(8).lowercased())"
    var earlier: [String: Any] = [
      "apiVersion": "openjoystickdriver/v1alpha1", "kind": "Diagnosis", "checks": [],
      "timings": [],
    ]
    var other = earlier
    earlier["bundle"] = "/tmp/support.json"
    other[unknown] = "/tmp/support.json"
    let schema = "cli-output.schema.json#/$defs/diagnose"

    let first = try issues(in: earlier, against: schema)
    let second = try issues(in: other, against: schema)

    #expect(!first.isEmpty)
    #expect(first.map { $0.replacingOccurrences(of: "bundle", with: "<field>") } == second.map {
      $0.replacingOccurrences(of: unknown, with: "<field>")
    })
  }
}
