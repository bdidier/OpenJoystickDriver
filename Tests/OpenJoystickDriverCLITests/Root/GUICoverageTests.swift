import ArgumentParser
import Foundation
import Testing

@testable import OpenJoystickDriverCLI

/// Every command has a GUI place in the D10 matrix (`GUICoverageMatrix`), and every CLI leaf and
/// behavior-changing option names the GUI symbol that performs it or is CLI-only (D10), per
/// `GUICoverageEntries`.
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
  func everyLeafAndOptionOfTheRealTreeIsCoveredOrCLIOnly() throws {
    let surface = try CLISurface.items()
    #expect(surface.count > 100)
    var uncovered: [String] = []
    for item in surface where !isCLIOnly(item) {
      if !GUICoverageEntries.entries.contains(where: {
        $0.command == item.command && $0.option == item.option
      }) {
        uncovered.append(item.key)
      }
    }
    #expect(
      uncovered.isEmpty,
      "CLI leaves and options with no GUI symbol or CLI-only entry: \(uncovered)"
    )
  }

  @Test
  func everyEntryAndCLIOnlyItemNamesARealLeafOrOption() throws {
    let surface = Set(try CLISurface.items())
    let staleEntries = GUICoverageEntries.entries.filter {
      !surface.contains(CLISurfaceItem(command: $0.command, option: $0.option))
    }.map(\.key)
    #expect(staleEntries.isEmpty, "entries with no CLI leaf or option: \(staleEntries)")
    let staleCLIOnly = GUICoverageEntries.cliOnly.filter { item in
      !surface.contains { matches(item, $0) }
    }.map { ($0.command ?? ["*"]).joined(separator: " ") + " " + ($0.option ?? "") }
    #expect(staleCLIOnly.isEmpty, "CLI-only items with no CLI leaf or option: \(staleCLIOnly)")
  }

  @Test
  func noItemIsBothInTheMatrixAndCLIOnly() throws {
    let both = try CLISurface.items().filter { item in
      isCLIOnly(item)
        && GUICoverageEntries.entries.contains {
          $0.command == item.command && $0.option == item.option
        }
    }.map(\.key)
    #expect(both.isEmpty, "items with a GUI symbol and a CLI-only entry: \(both)")
    let keys = GUICoverageEntries.entries.map(\.key)
    #expect(Set(keys).count == keys.count, "duplicate entries")
  }

  @Test
  func everyNamedGUISymbolIsDeclaredAndReferencedInTheGUI() {
    #expect(GUISources.text.contains("MainWindowProblemBanner"))
    var missing: [String] = []
    for entry in GUICoverageEntries.entries {
      let symbol = entry.symbol
      if !GUISources.isDeclaredAndReferenced(symbol) { missing.append("\(entry.key): \(symbol)") }
    }
    #expect(missing.isEmpty, "GUI symbols that do not exist: \(missing)")
  }

  @Test
  func aSymbolTheGUIDoesNotDeclareIsReported() {
    #expect(!GUISources.isDeclaredAndReferenced("noSuchGUISymbolAnywhere"))
    #expect(
      GUISources.strippingCommentsAndStrings("// a\nlet b = \"c \\(d) e\" /* f */")
        == "\nlet b = d "
    )
    #expect(GUISources.isDeclaredAndReferenced("MainWindowProblemBanner"))
  }

  @Test
  func theD10TextNamesEveryCLIOnlyItem() throws {
    let design = try String(
      contentsOf: GUISources.root.appendingPathComponent(
        "openspec/changes/platform-neutral-redesign/design.md"
      ),
      encoding: .utf8
    )
    let start = try #require(design.range(of: "### D10"))
    let end = try #require(design.range(of: "### D11"))
    let section = String(design[start.lowerBound..<end.lowerBound])
    let listStart = try #require(section.range(of: "are listed as CLI-only:"))
    let listEnd = try #require(section.range(of: "`GUICoverageEntries` lists exactly these"))
    let list = String(section[listStart.upperBound..<listEnd.lowerBound])
    let named = Set(
      try #require(try? NSRegularExpression(pattern: "`([^`]+)`")).matches(
        in: list,
        range: NSRange(list.startIndex..., in: list)
      ).compactMap { Range($0.range(at: 1), in: list).map { String(list[$0]) } }
    )
    // An option of one command is named together with that command.
    let expected = Set(
      GUICoverageEntries.cliOnly.flatMap { item -> [String] in
        let command = (item.command ?? []).joined(separator: " ")
        guard let option = item.option else { return [command] }
        return item.command == nil ? [option] : [option, command]
      }
    )
    #expect(
      named == expected,
      """
      D10 lacks \(expected.subtracting(named).sorted()); \
      D10 names more: \(named.subtracting(expected).sorted())
      """
    )
  }

  @Test
  func aFakeCommandWithNoGUIPlaceIsReported() {
    let paths = CLICommandTree.paths(of: FakeRoot.self)
    #expect(paths == [["status"], ["frobnicate"], ["frobnicate", "run"]])
    #expect(GUICoverageMatrix.unmapped(in: paths) == [["frobnicate", "run"]])
  }
}

private func isCLIOnly(_ item: CLISurfaceItem) -> Bool {
  GUICoverageEntries.cliOnly.contains { matches($0, item) }
}

private func matches(_ cliOnly: CLIOnlyItem, _ item: CLISurfaceItem) -> Bool {
  // A CLI-only leaf makes its options CLI-only too.
  if cliOnly.option == nil { return cliOnly.command == item.command }
  return cliOnly.option == item.option
    && (cliOnly.command == nil || cliOnly.command == item.command)
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
