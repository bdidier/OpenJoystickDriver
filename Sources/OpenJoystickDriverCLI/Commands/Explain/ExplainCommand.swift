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

    private enum CodingKeys: String, CodingKey {
      case code, area, explanation, exitCode, wire
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
    guard let id = ErrorCode(typed: code) else {
      throw CLIFailure.usage(CLILocalized.format("cli.explain.unknown", code))
    }
    let facts = id.facts
    return Result(
      code: facts.code,
      domain: facts.domain,
      area: facts.area,
      explanation: facts.explanation,
      exitCode: facts.exitCode,
      wire: facts.wire
    )
  }
}
