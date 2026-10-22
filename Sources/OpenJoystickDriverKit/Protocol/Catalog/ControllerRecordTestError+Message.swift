import Foundation

extension ControllerRecordTestError {
  /// The failure in words. `capture` and `expectation` name the two inputs, and `model` is the
  /// record under test.
  public func message(model: ControllerModelID, capture: String, expectation: String) -> String {
    let localization = Localization()
    switch self {
    case .capture(let line, let problem):
      return localization.formatted(
        "cli.record.test.captureInvalid",
        arguments: [capture, "line \(line): \(problem)"]
      )
    case .expectation(let problem):
      return localization.formatted(
        "cli.record.test.expectInvalid",
        arguments: [expectation, problem]
      )
    case .replay(.noParser):
      return localization.formatted("cli.record.test.noParser", arguments: [model.description])
    case .replay(.invalidReport(let index)):
      return localization.formatted(
        "cli.record.test.parseFailed",
        arguments: [model.description, index + 1, capture]
      )
    case .replay(.noInput):
      return localization.formatted(
        "cli.record.test.noInput",
        arguments: [capture, model.description]
      )
    }
  }
}
