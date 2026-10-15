import ArgumentParser
import Testing

@testable import OpenJoystickDriverCLI

/// Task 17.5: every command has a GUI place in the D10 matrix (`GUICoverageMatrix`).
struct GUICoverageTests {
  @Test
  func everyCommandOfTheRealTreeHasAGUIPlace() {
    let paths = CLICommandTree.paths()
    #expect(!paths.isEmpty)
    let unmapped = GUICoverageMatrix.unmapped(in: paths).map { $0.joined(separator: " ") }
    #expect(unmapped.isEmpty, "commands with no GUI place: \(unmapped)")
  }

  @Test
  func everyMatrixEntryNamesARealCommand() {
    let stale = GUICoverageMatrix.stale(in: CLICommandTree.paths()).map {
      $0.prefix.joined(separator: " ")
    }
    #expect(stale.isEmpty, "matrix entries with no command: \(stale)")
  }

  @Test
  func everyFieldPlaceNamesARealCommandAndSchemaField() throws {
    let paths = CLICommandTree.paths()
    for entry in GUICoverageMatrix.fields {
      #expect(paths.contains(entry.command), "no command \(entry.command)")
      var node = try #require(
        CLIOutputSchema.definitions[CLIOutputSchema.definitionName(for: entry.command)]
          as? [String: Any]
      )
      for name in entry.field.split(separator: ".") {
        let properties = try #require(node["properties"] as? [String: Any])
        node = try #require(properties[String(name)] as? [String: Any], "\(entry.field)")
      }
      #expect(!entry.place.isEmpty)
    }
  }

  @Test
  func aFakeCommandWithNoGUIPlaceIsReported() {
    let paths = CLICommandTree.paths(of: FakeRoot.self)
    #expect(paths == [["status"], ["frobnicate"], ["frobnicate", "run"]])
    #expect(GUICoverageMatrix.unmapped(in: paths) == [["frobnicate", "run"]])
  }
}

private struct FakeRoot: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ojd",
    subcommands: [StatusCommand.self, FakeGroup.self]
  )
}

private struct FakeGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "frobnicate",
    subcommands: [FakeRun.self]
  )
}

private struct FakeRun: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "run")
}
