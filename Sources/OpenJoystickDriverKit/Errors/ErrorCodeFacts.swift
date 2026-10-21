import Foundation

/// Everything `ojd explain` prints for an error code. The app's Explain Error Code sheet shows
/// the same facts.
public struct ErrorCodeFacts: Equatable, Sendable {
  public let code: String
  public let domain: String
  /// The localized name of the area that raises the code.
  public let area: String
  public let explanation: String
  /// The exit status of `ojd` for a command-line code; nil for other areas.
  public let exitCode: Int32?
  /// The RPC wire value of a remapping code; nil for other areas.
  public let wire: String?
}

extension ErrorCode {
  /// The exit status of `ojd` when it fails with this code; `Resources/ErrorCodes.json` lists it
  /// as `exitCode`. A code of another area, such as a remapping code, is a plain failure (1).
  public var commandLineExitStatus: Int32 {
    switch self {
    case .unknownCommand, .usage, .confirmationRequired, .noAccessScope, .duplicateTokenName,
      .invalidTokenName, .invalidWebOrigin, .webPortUnavailable, .controlScopeWithOrigins:
      64
    case .serviceUnavailable, .requestListenerStopped, .noApplicationAnswered: 69
    case .permissionMissing, .notificationsDenied: 77
    case .installedCLIFailed: 127
    default: 1
    }
  }

  public var facts: ErrorCodeFacts {
    let localization = Localization()
    let area: String
    switch domain {
    case .endpoint: area = localization.string("cli.explain.area.endpoint")
    case .commandLine: area = localization.string("cli.explain.area.cli")
    case .remapping: area = localization.string("cli.explain.area.remapping")
    case .mod: area = localization.string("cli.explain.area.mod")
    case .document: area = localization.string("cli.explain.area.document")
    }
    return ErrorCodeFacts(
      code: rawValue,
      domain: domain.rawValue,
      area: area,
      explanation: localizedExplanation,
      exitCode: domain == .commandLine ? commandLineExitStatus : nil,
      wire: domain == .remapping
        ? ApplicationServiceRemappingRPCError.Code.allCases.first { $0.errorCode == self }?.rawValue
        : nil
    )
  }
}
