import Foundation

extension ControllerRecordTestError {
  /// The failure in words. `capture` and `expectation` name the two inputs, and `model` is the
  /// record under test.
  public func message(model: ControllerModelID, capture: String, expectation: String) -> String {
    let localization = Localization()
    switch self {
    case .capture(let line, let problem):
      return localization.formatted(
        "cli.record.test.capture_invalid",
        arguments: [capture, "line \(line): \(problem)"]
      )
    case .expectation(let problem):
      return localization.formatted(
        "cli.record.test.expect_invalid",
        arguments: [expectation, problem]
      )
    case .replay(.noParser):
      return localization.formatted("cli.record.test.no_parser", arguments: [model.description])
    case .replay(.invalidReport(let index)):
      return localization.formatted(
        "cli.record.test.parse_failed",
        arguments: [model.description, index + 1, capture]
      )
    case .replay(.noInput):
      return localization.formatted(
        "cli.record.test.no_input",
        arguments: [capture, model.description]
      )
    }
  }
}
