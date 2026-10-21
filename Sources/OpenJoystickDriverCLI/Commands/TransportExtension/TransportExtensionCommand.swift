import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct TransportExtensionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "transport-extension",
    abstract: CLILocalized.text(
      "cli.transport_extension.abstract"
    ),
    subcommands: [
      TransportExtensionStatusCommand.self, TransportExtensionActivateCommand.self,
      TransportExtensionDeactivateCommand.self,
    ]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `ojd transport-extension status --json` result.
///
/// `detail` is the `systemextensionsctl` record, the unexpected bundle identifier, or the
/// reason the state is unavailable; it is absent when there is nothing to add.
struct TransportExtensionStatusReport: Encodable, Equatable {
  let bundle: StatusReport.Extension.Bundle
  let registration: StatusReport.Extension.Registration
  let detail: String?

  init(_ status: ExtensionStatus) {
    let summary = StatusReport.Extension(status)
    bundle = summary.bundle
    registration = summary.registration
    detail = status.detail
  }
}

struct TransportExtensionStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.transport_extension.status.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.transport_extension.status.discussion"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = StatusCommand.extensionProbe()
      let report = TransportExtensionStatusReport(status)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain([
          ["bundle", CommandLineName.kebab(report.bundle.rawValue)],
          ["registration", CommandLineName.kebab(report.registration.rawValue)],
        ])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.transport_extension.status.bundle",
            CommandLineName.kebab(report.bundle.rawValue)
          )
        )
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.transport_extension.status.registration",
            CommandLineName.kebab(report.registration.rawValue)
          )
        )
        if let detail = report.detail, report.registration != .unavailable {
          CLIOutput.stdout(detail)
        }
      }
      if case .unavailable(let reason) = status.registration {
        throw CLIFailure(
          .systemRequestFailed,
          CLILocalized.format(
            "cli.transport_extension.status.unavailable",
            reason
          )
        )
      }
    }
  }
}

/// The `--json` result of `transport-extension activate` and `transport-extension deactivate`.
struct TransportExtensionResult: Encodable, Equatable {
  enum State: String, Encodable {
    case active = "Active"
    case inactive = "Inactive"
    case awaitingApproval = "AwaitingApproval"
  }

  let state: State
}

private func submit(
  _ action: TransportExtensionSubmission.Action,
  done state: TransportExtensionResult.State,
  message: String
) async throws {
  let outcome = try await TransportExtensionSubmission.submit(action)
  let result: TransportExtensionResult.State
  switch outcome {
  case .active, .inactive: result = state
  case .awaitingApproval: result = .awaitingApproval
  case .cancelled: throw CancellationError()
  case .timedOut:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "cli.transport_extension.timeout"
      )
    )
  case .failed:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "cli.transport_extension.submit_failed"
      )
    )
  }
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(TransportExtensionResult(state: result))
  case .plain: CLIOutput.plain([["state", CommandLineName.kebab(result.rawValue)]])
  case .human:
    if result == .awaitingApproval {
      CLIOutput.stderr(
        CLILocalized.text(
          "cli.transport_extension.approval"
        )
      )
    } else {
      CLIOutput.success(message)
    }
  }
}

struct TransportExtensionActivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "activate",
    abstract: CLILocalized.text(
      "cli.transport_extension.activate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.transport_extension.activate.discussion"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await submit(
        .activate,
        done: .active,
        message: CLILocalized.text("cli.transport_extension.activated")
      )
    }
  }
}

struct TransportExtensionDeactivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "cli.transport_extension.deactivate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.transport_extension.deactivate.discussion"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await submit(
        .deactivate,
        done: .inactive,
        message: CLILocalized.text("cli.transport_extension.deactivated")
      )
    }
  }
}
