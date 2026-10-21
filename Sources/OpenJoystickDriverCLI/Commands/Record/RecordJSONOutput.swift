import Foundation
import OpenJoystickDriverKit

/// The `--json` output of a command that embeds a record document.
enum RecordJSONOutput {
  /// Prints `value` with ``CLIOutput/json(_:kind:)``. A record number that `OrderedJSON` cannot
  /// encode without changing its value, such as `1e400` or an integer of 40 digits, fails with
  /// ``ErrorCode/unwritableJSONNumber`` and the text `message` gives for the number and its place
  /// in the `--json` document.
  static func print(
    message: (_ number: String, _ path: String) -> String,
    _ value: some Encodable
  ) throws {
    do {
      try CLIOutput.json(value)
    } catch EncodingError.invalidValue(let number as String, let context) {
      throw CLIFailure(
        .unwritableJSONNumber,
        message(number, path(context.codingPath))
      )
    }
  }

  /// `codingPath` as dotted member names and array indexes, such as `record.modes.0.id`.
  static func path(_ codingPath: [any CodingKey]) -> String {
    codingPath.map { key in key.intValue.map(String.init) ?? key.stringValue }
      .joined(separator: ".")
  }
}
