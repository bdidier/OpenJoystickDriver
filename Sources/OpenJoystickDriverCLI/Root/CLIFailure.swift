import Foundation
import OpenJoystickDriverKit

/// The exit codes `ojd` documents in its root help and the command-line docs.
enum CLIExitCode: Int32, Sendable {
  case success = 0
  case failure = 1
  case usage = 64
  case serviceUnavailable = 69
  case permissionDenied = 77
  /// The `ojd` of a repository build could not hand the command to the installed app.
  case installedCLIFailed = 127
  case interrupted = 130

  /// The exit code of the failure that `id` names.
  init(for id: ErrorCode) {
    guard let code = Self(rawValue: id.commandLineExitStatus) else {
      preconditionFailure("\(id.rawValue) has an exit status that CLIExitCode does not list.")
    }
    self = code
  }
}

/// An expected failure that `ojd` reports as `error[<code>]: <message>` on stderr.
///
/// `id` is the stable error code, and the exit code follows from it. `message` states what
/// failed and how to fix it, already localized.
struct CLIFailure: Error, Equatable, Sendable {
  let id: ErrorCode
  let message: String

  var code: CLIExitCode { CLIExitCode(for: id) }

  /// The line `ojd` writes on stderr.
  var line: String { Self.prefix(id) + message }

  /// The start of each error line of `ojd`, which names the stable code.
  static func prefix(_ id: ErrorCode) -> String { "error[\(id.rawValue)]: " }

  init(_ id: ErrorCode, _ message: String) {
    self.id = id
    self.message = message
  }

  static var serviceUnavailable: Self {
    Self(
      .serviceUnavailable,
      CLILocalized.text(
        "cli.shared.error.serviceUnavailable"
      )
    )
  }

  /// The service did not complete a request; `id` is the service's own code when it sent one.
  static func serviceRequestFailed(_ detail: String, id: ErrorCode = .serviceRequestFailed) -> Self
  {
    Self(
      id,
      CLILocalized.format(
        "cli.shared.error.serviceRequestFailed",
        // The service's message ends with a period; the format adds its own.
        detail.hasSuffix(".") ? String(detail.dropLast()) : detail
      )
    )
  }

  /// A macOS permission that `permissionName` names is missing; exit code 77.
  static func permissionMissing(_ permissionName: String) -> Self {
    Self(
      .permissionMissing,
      CLILocalized.format(
        "cli.shared.error.permissionMissing",
        permissionName
      )
    )
  }

  static func usage(_ message: String) -> Self { Self(.usage, message) }
}
