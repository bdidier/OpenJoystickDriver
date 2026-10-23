import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// What `ojd config set` and `ojd config unset` share: they set or remove one tuning key in the
/// user's patch of a controller model, or in `all.patch.json`, and print the same result.
enum ConfigChange {
  /// The `--json` result. `value` is absent for `unset`, and `previous` while no layer set the key.
  struct Result: Encodable, Equatable {
    let key: String
    let value: Double?
    let previous: Double?
    let controller: String?
    let file: String
    let created: Bool
    let removesFile: Bool
  }

  /// The tuning key named `name`.
  static func key(_ name: String) throws -> ControllerTuning.Key {
    guard let key = ControllerTuning.Key(rawValue: name) else {
      throw ValidationError(
        CLILocalized.format(
          "cli.config.group.unknownKey",
          name,
          ControllerTuning.Key.allCases.map(\.rawValue).joined(separator: ", ")
        )
      )
    }
    return key
  }

  /// The number written as `text`.
  static func number(_ text: String) throws -> Double {
    guard let number = Double(text), number.isFinite else {
      throw ValidationError(CLILocalized.format("cli.config.group.notNumber", text))
    }
    return number
  }

  /// The edit that `KEY` and `VALUE` name; a nil `value` removes the key.
  static func edit(key name: String, value: String?) throws -> ControllerRecordWriter.TuningEdit {
    let key = try key(name)
    guard let value else { return .remove(key) }
    return .set(key, try number(value))
  }

  static func run(
    _ edit: ControllerRecordWriter.TuningEdit,
    controller model: ControllerModelID?,
    global: GlobalOptions
  ) async throws {
    try await global.run {
      let target = model.map(ControllerRecordWriter.Target.model) ?? .allControllers
      let change = try change(edit, for: target, model: model)
      try write(change)
      var value: Double?
      if case .set(_, let number) = edit { value = number }
      let result = Result(
        key: edit.key.rawValue,
        value: value,
        previous: change.previousTuning,
        controller: model?.description,
        file: change.file.path,
        created: change.created,
        removesFile: change.data == nil
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [result.key] + [result.value.map(ConfigShowCommand.text)].compactMap { $0 }
            + [result.file]
        ])
      case .human: printHuman(result)
      }
    }
  }

  private static func printHuman(_ result: Result) {
    CLIOutput.success(
      result.value.map {
        CLILocalized.format(
          "cli.config.set.success",
          result.key,
          ConfigShowCommand.text($0),
          result.file
        )
      } ?? CLILocalized.format("cli.config.unset.success", result.key, result.file)
    )
  }

  private static func change(
    _ edit: ControllerRecordWriter.TuningEdit,
    for target: ControllerRecordWriter.Target,
    model: ControllerModelID?
  ) throws -> ControllerRecordWriter.Change {
    do {
      return try ControllerRecordWriter.change(
        edit,
        for: target,
        records: RecordStore.load(),
        directory: RecordStore.directory
      )
    } catch {
      switch error {
      case .refused(.noRecord):
        let identity = model?.description ?? ""
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.config.group.noRecord", identity, identity)
        )
      case .refused(.invalidFile(let problem)), .refused(.invalidResult(let problem)):
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format("cli.config.group.invalid", edit.key.rawValue, problem)
        )
      case .notSet(let key):
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.config.unset.notSet", key.rawValue)
        )
      }
    }
  }

  private static func write(_ change: ControllerRecordWriter.Change) throws {
    do { try ControllerRecordWriter.write(change) } catch {
      throw CLIFailure(
        .fileAccessFailed,
        CLILocalized.format(
          "cli.record.install.failed",
          change.file.path,
          error.localizedDescription
        )
      )
    }
  }
}
