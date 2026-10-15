import Foundation

/// The one table of words that 0.6.0 renamed to an OS-neutral word (task 17.1).
///
/// An old word is still refused everywhere; this table only lets the refusal name the new word.
/// Add one row per rename, whatever the part of 17.1 that makes it. Each row is one line of the form
/// `Rename(kind: .flag(command: "diagnose"), old: "--bundle", new: "--output")`, so that
/// `Tests/RepositoryScripts/test_renamed_words.py` can read the rows and check that no schema
/// still uses the old word.
///
/// - `.flag(command:)`: a command-line flag of `command`; the `--old=value` form matches too.
/// - `.value(command:)`: a value typed after a flag of `command`.
/// - `.field(in:)`: a property of the document kind in the schema file `in`, such as
///   `report.schema.json` or `cli-output.schema.json#/$defs/diagnose`. The test validator adds the
///   hint to the error for the unknown property.
///
/// The CLI reads the flag and value rows in `CLI.parseAndRun`; the test validator
/// (`JSONSchemaFiles`) reads the field rows.
public enum RenamedWords {
  public enum Kind: Equatable, Sendable {
    case flag(command: String)
    case value(command: String)
    case field(in: String)
  }

  public struct Rename: Equatable, Sendable {
    public let kind: Kind
    public let old: String
    public let new: String
  }

  public static let renames: [Rename] = [
    Rename(kind: .flag(command: "diagnose"), old: "--bundle", new: "--output"),
    Rename(kind: .field(in: "report.schema.json"), old: "macOSVersion", new: "osVersion"),
    Rename(
      kind: .field(in: "report.schema.json"),
      old: "appleGameControllerAudit",
      new: "systemGamepadAudit"
    ),
    Rename(
      kind: .field(in: "report.schema.json"),
      old: "appleExactDeviceCount",
      new: "systemExactDeviceCount"
    ),
    Rename(
      kind: .field(in: "report.schema.json"),
      old: "appleIdentifiers",
      new: "systemIdentifiers"
    ),
    Rename(
      kind: .field(in: "report.schema.json"),
      old: "skippedAppleDeviceCount",
      new: "skippedSystemDeviceCount"
    ),
    Rename(
      kind: .field(in: "cli-output.schema.json#/$defs/diagnose"),
      old: "bundle",
      new: "output"
    ),
  ]

  /// The rename that `arguments` trips, or nil when no renamed flag or value is used.
  public static func match(arguments: [String]) -> Rename? {
    let typed = arguments[..<(arguments.firstIndex(of: "--") ?? arguments.endIndex)]
    return renames.first { rename in
      switch rename.kind {
      case .flag(let command):
        return typed.contains(command)
          && typed.contains { $0 == rename.old || $0.hasPrefix(rename.old + "=") }
      case .value(let command):
        return typed.contains(command)
          && typed.contains { $0 == rename.old || $0.hasSuffix("=" + rename.old) }
      case .field:
        return false
      }
    }
  }

  /// The new word for the property `old` of a document validated against `file`, or nil.
  public static func newField(for old: String, in file: String) -> String? {
    renames.first { rename in
      guard case .field(let location) = rename.kind else { return false }
      return rename.old == old && location.hasPrefix(file)
    }?.new
  }
}
