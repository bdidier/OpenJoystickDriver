import ArgumentParser
import Foundation
import OpenJoystickDriverKit

extension PacketLogEntry {
  /// The packet's bytes, from its `hex` string.
  var reportBytes: [UInt8] { hex.split(separator: " ").compactMap { UInt8($0, radix: 16) } }
}

struct RecordTestCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: CLILocalized.text("cli.record.test.abstract"),
    discussion: CLILocalized.text("cli.record.test.discussion")
  )

  /// The `--json` result. `differences` is empty when the states match.
  struct Result: Encodable, Equatable {
    /// One field of the controller state that differs; `expected` and `actual` are its JSON.
    struct Difference: Encodable, Equatable {
      let field: String
      let expected: String
      let actual: String
    }

    let identity: String
    let matches: Bool
    let inputReports: Int
    let differences: [Difference]
  }

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var model: ControllerModelID

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.test.packets"),
      valueName: "CAPTURE"
    )
  )
  var packets: String

  @Option(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.test.expect"),
      valueName: "STATE"
    )
  )
  var expect: String

  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      RecordStore.warn(set.problems.filter { $0.model == model })
      guard let record = set.records[model] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.record.show.not_found", model.description)
        )
      }
      let outcome = try test(
        record,
        capture: RecordStore.read(packets),
        expectation: RecordStore.read(expect)
      )
      let result = Result(
        identity: model.description,
        matches: outcome.matches,
        inputReports: outcome.inputReports,
        differences: outcome.differences.map {
          Result.Difference(field: $0.field, expected: $0.expected, actual: $0.actual)
        }
      )
      try print(result)
      if !outcome.matches {
        throw CLIFailure(
          .recordTestMismatch,
          CLILocalized.format(
            "cli.record.test.mismatch",
            model.description,
            expect,
            outcome.differences.count
          )
        )
      }
    }
  }

  private func test(
    _ record: ControllerRecord,
    capture: Data,
    expectation: Data
  ) throws -> ControllerRecordTestResult {
    do { return try record.test(capture: capture, expectation: expectation) } catch let error
      as ControllerRecordTestError
    {
      throw CLIFailure(
        .invalidInputFile,
        error.message(model: model, capture: packets, expectation: expect)
      )
    }
  }

  private func print(_ result: Result) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain: CLIOutput.plain(result.differences.map { [$0.field, $0.expected, $0.actual] })
    case .human:
      if result.matches {
        CLIOutput.success(
          CLILocalized.format("cli.record.test.matched", result.identity, result.inputReports)
        )
      }
      for difference in result.differences {
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.record.test.difference",
            difference.field,
            difference.expected,
            difference.actual
          )
        )
      }
    }
  }
}
