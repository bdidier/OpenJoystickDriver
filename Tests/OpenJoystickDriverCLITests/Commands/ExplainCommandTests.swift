import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct ExplainCommandTests {
  private struct Catalog: Decodable {
    struct Entry: Decodable {
      let code: String
      let domain: String
      let exitCode: Int32?
      let status: String
      let retiredIn: String?
    }
    let codes: [Entry]
  }

  @Test
  func aCommandLineCodeShowsItsExitCode() async throws {
    let human = await CLIRun.run(["explain", "E2004"])
    let json = await CLIRun.run(["explain", "E2004", "--json"])

    #expect(human.code == 0)
    #expect(human.standardOutput.hasPrefix("E2004\n"))
    #expect(human.standardOutput.contains("69"))
    #expect(human.standardError.isEmpty)
    #expect(try json.json()["code"] as? String == "E2004")
    #expect(try json.json()["exitCode"] as? Int == 69)
    #expect(try json.json()["wire"] == nil)
  }

  @Test
  func aRemappingCodeShowsItsWireValueAndIgnoresCase() async throws {
    let human = await CLIRun.run(["explain", "e3013"])
    let json = await CLIRun.run(["explain", "e3013", "--json"])

    #expect(human.code == 0)
    #expect(human.standardOutput.contains("profile_not_found"))
    #expect(try json.json()["code"] as? String == "E3013")
    #expect(try json.json()["wire"] as? String == "profile_not_found")
    #expect(try json.json()["exitCode"] == nil)
  }

  @Test
  func aRetiredCodeSaysInWhichVersionItWasRetired() async throws {
    let human = await CLIRun.run(["explain", "e1003"])
    let json = await CLIRun.run(["explain", "E1003", "--json"])
    let plain = await CLIRun.run(["explain", "E1003", "--plain"])

    #expect(human.code == 0)
    #expect(human.standardOutput.hasPrefix("E1003\n"))
    #expect(human.standardOutput.contains("Retired in 0.6.0-alpha.1."))
    #expect(human.standardError.isEmpty)
    #expect(try json.json()["code"] as? String == "E1003")
    #expect(try json.json()["retiredIn"] as? String == "0.6.0-alpha.1")
    #expect(try json.json()["explanation"] as? String == "Retired in 0.6.0-alpha.1.")
    #expect(try json.json()["exitCode"] == nil)
    #expect(plain.code == 0)
    #expect(plain.standardOutput.hasPrefix("E1003"))
  }

  @Test
  func everyRetiredCatalogCodeIsExplained() async throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Commands
      .deletingLastPathComponent()  // OpenJoystickDriverCLITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository root
      .appendingPathComponent("Resources/ErrorCodes.json")
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    let retired = catalog.codes.filter { $0.status == "retired" }

    #expect(!retired.isEmpty)
    for entry in retired {
      let run = await CLIRun.run(["explain", entry.code, "--json"])
      #expect(run.code == 0, "\(entry.code)")
      #expect(try run.json()["retiredIn"] as? String == entry.retiredIn, "\(entry.code)")
    }
  }

  @Test
  func anUnknownCodeIsAUsageFailure() async {
    let run = await CLIRun.run(["explain", "E9999"])

    #expect(run.code == 64)
    #expect(run.standardOutput.isEmpty)
    #expect(run.standardError.hasPrefix("error[E2003]: "))
    #expect(run.standardError.contains("E9999"))
  }

  @Test
  func everyCodeHasAnExplanation() async throws {
    for id in ErrorCode.allCases {
      let json = try await CLIRun.run(["explain", id.rawValue, "--json"]).json()
      let text = try #require(json["explanation"] as? String)
      #expect(!text.isEmpty && text != "error.\(id.rawValue)", "\(id.rawValue)")
    }
  }

  @Test
  func theExitCodeOfEachCommandLineCodeIsTheCatalogOne() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Commands
      .deletingLastPathComponent()  // OpenJoystickDriverCLITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository root
      .appendingPathComponent("Resources/ErrorCodes.json")
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    let documented = Dictionary(
      uniqueKeysWithValues: catalog.codes.compactMap { entry in
        entry.exitCode.map { (entry.code, $0) }
      }
    )

    for id in ErrorCode.allCases where id.domain == .commandLine {
      #expect(CLIExitCode(for: id).rawValue == documented[id.rawValue], "\(id.rawValue)")
    }
  }
}
