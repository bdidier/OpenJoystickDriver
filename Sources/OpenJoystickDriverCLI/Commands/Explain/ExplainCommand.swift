import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ExplainCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "explain",
    abstract: CLILocalized.text(
      "cli.explain.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.explain.discussion"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.explain.code"),
      valueName: "code"
    )
  )
  var code: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  private struct Result: Encodable {
    let code: String
    let domain: String
    let area: String
    let explanation: String
    let exitCode: Int32?
    let wire: String?
    let retiredIn: String?

    private enum CodingKeys: String, CodingKey {
      case code, area, explanation, exitCode, wire, retiredIn
    }
  }

  func run() async throws {
    try await global.run {
      let result = try Self.result(for: code)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.code, result.domain,
            result.exitCode.map(String.init) ?? result.wire ?? "",
          ]
        ])
      case .human:
        CLIOutput.stdout(result.code)
        CLIOutput.stdout(
          CLILocalized.format("cli.explain.area", result.area)
        )
        if let exitCode = result.exitCode {
          CLIOutput.stdout(
            CLILocalized.format("cli.explain.exit_code", String(exitCode))
          )
        }
        if let wire = result.wire {
          CLIOutput.stdout(CLILocalized.format("cli.explain.wire", wire))
        }
        CLIOutput.stdout()
        CLIOutput.stdout(result.explanation)
      }
    }
  }

  private static func result(for code: String) throws -> Result {
    if let id = ErrorCode(rawValue: code.uppercased()) {
      return Result(
        code: id.rawValue,
        domain: id.domain.rawValue,
        area: area(of: id.domain),
        explanation: id.localizedExplanation,
        exitCode: id.domain == .commandLine ? CLIExitCode(for: id).rawValue : nil,
        wire: id.domain == .remapping
          ? ApplicationServiceRemappingRPCError.Code.allCases.first { $0.errorCode == id }?.rawValue
          : nil,
        retiredIn: nil
      )
    }
    if let retired = RetiredErrorCode.named(code) {
      return Result(
        code: retired.code,
        domain: retired.domain.rawValue,
        area: area(of: retired.domain),
        explanation: CLILocalized.format("cli.explain.retired", retired.retiredIn),
        exitCode: nil,
        wire: nil,
        retiredIn: retired.retiredIn
      )
    }
    throw CLIFailure.usage(CLILocalized.format("cli.explain.unknown", code))
  }

  private static func area(of domain: ErrorCode.Domain) -> String {
    switch domain {
    case .endpoint: CLILocalized.text("cli.explain.area.endpoint")
    case .commandLine: CLILocalized.text("cli.explain.area.cli")
    case .remapping: CLILocalized.text("cli.explain.area.remapping")
    case .mod: CLILocalized.text("cli.explain.area.mod")
    case .document: CLILocalized.text("cli.explain.area.document")
    }
  }
}
