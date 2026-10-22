import Foundation
import OpenJoystickDriverKit

/// A number the Soak Test sheet asks for; each is an option of `ojd diagnose --soak`.
enum SoakTestField: CaseIterable {
  case seconds
  case interval
  case residentLimit
  case footprintLimit

  var labelKey: String {
    switch self {
    case .seconds: "ui.developer.soakDuration"
    case .interval: "ui.developer.soakInterval"
    case .residentLimit: "ui.developer.soakResidentLimit"
    case .footprintLimit: "ui.developer.soakFootprintLimit"
    }
  }

  /// The values the command accepts: `--soak`, `--interval-ms`, `--rss-limit-mib` and
  /// `--footprint-limit-mib`.
  var range: ClosedRange<Int> {
    switch self {
    case .seconds: ApplicationServiceRuntimeHealthSampler.secondsRange
    case .interval: ApplicationServiceRuntimeHealthSampler.intervalMillisecondsRange
    case .residentLimit, .footprintLimit: RuntimeHealthPolicy.limitMiBRange
    }
  }
}

/// Why the entered numbers cannot start a soak test.
enum SoakTestProblem: Error, Equatable {
  case notANumber(SoakTestField)
  case outOfRange(SoakTestField)
  case tooManySamples(Int)

  var message: String {
    switch self {
    case .notANumber(let field):
      OJDLocalized.formatted("ui.developer.soakNotANumber", OJDLocalized.string(field.labelKey))
    case .outOfRange(let field):
      OJDLocalized.formatted(
        "ui.developer.soakOutOfRange",
        OJDLocalized.string(field.labelKey),
        field.range.lowerBound,
        field.range.upperBound
      )
    case .tooManySamples(let count):
      OJDLocalized.formatted("ui.developer.soakTooManySamples", count)
    }
  }
}

/// The numbers of one soak test, all within the ranges of `ojd diagnose --soak`.
struct SoakTestSettings: Equatable {
  let seconds: Int
  let intervalMilliseconds: Int
  let residentLimitMiB: Int
  let footprintLimitMiB: Int

  var policy: RuntimeHealthPolicy {
    RuntimeHealthPolicy(residentLimitMiB: residentLimitMiB, footprintLimitMiB: footprintLimitMiB)
  }
}

/// The text fields of the Soak Test sheet, started at the values of `ojd diagnose`: a 60 second
/// run, which is the shortest the runtime health verdict accepts, one sample per second, no
/// resident size limit and a 512 MiB footprint limit.
struct SoakTestForm: Equatable {
  var seconds = "60"
  var interval = "1000"
  var residentLimit = "0"
  var footprintLimit = "512"

  func text(of field: SoakTestField) -> String {
    switch field {
    case .seconds: seconds
    case .interval: interval
    case .residentLimit: residentLimit
    case .footprintLimit: footprintLimit
    }
  }

  /// The settings these fields describe, or the first problem, checked as the command checks.
  func settings() -> Result<SoakTestSettings, SoakTestProblem> {
    var numbers: [SoakTestField: Int] = [:]
    for field in SoakTestField.allCases {
      guard
        let number = Int(text(of: field).trimmingCharacters(in: .whitespacesAndNewlines))
      else { return .failure(.notANumber(field)) }
      guard field.range.contains(number) else { return .failure(.outOfRange(field)) }
      numbers[field] = number
    }
    let settings = SoakTestSettings(
      seconds: numbers[.seconds] ?? 0,
      intervalMilliseconds: numbers[.interval] ?? 0,
      residentLimitMiB: numbers[.residentLimit] ?? 0,
      footprintLimitMiB: numbers[.footprintLimit] ?? 0
    )
    let samples = ApplicationServiceRuntimeHealthSampler.sampleCount(
      seconds: settings.seconds,
      intervalMilliseconds: settings.intervalMilliseconds
    )
    guard samples <= ApplicationServiceRuntimeHealthSampler.maximumSampleCount else {
      return .failure(.tooManySamples(samples))
    }
    return .success(settings)
  }
}

enum SoakTestState: Equatable {
  case idle
  case running
  /// The `runtime-health` check of `ojd diagnose --soak`, as a pass, warning, failure or skip.
  case finished(ActivityCheckRow)
}

/// Runs the soak test of `ojd diagnose --soak` for the Soak Test sheet: it samples the service
/// process and shows the `runtime-health` check.
@MainActor
final class SoakTestModel: ObservableObject {
  /// What the model reads from the system; tests replace it.
  struct Source {
    /// Asks the service once, as `ojd diagnose` does; a stopped or failing service never throws.
    let snapshot: @MainActor () async -> DiagnoseServiceSnapshot
    /// The service process identifier, or nil when nothing answers. It connects to the service's
    /// socket, so it runs off the main actor.
    let processIdentifier: @Sendable () async -> Int32?
    let sample: @Sendable (Int32, SoakTestSettings) async throws -> RuntimeHealthSummary

    static func service(gateway: any ApplicationServiceGateway) -> Self {
      Self(
        snapshot: { await ActivityDiagnosticsChecks.serviceSnapshot(gateway) },
        processIdentifier: {
          await Task.detached { LocalServiceRPCClient.serverProcessIdentifier() }.value
        },
        sample: { processID, settings in
          try await ApplicationServiceRuntimeHealthSampler.sample(
            processID: processID,
            seconds: settings.seconds,
            intervalMilliseconds: settings.intervalMilliseconds,
            policy: settings.policy
          )
        }
      )
    }
  }

  @Published
  var form = SoakTestForm()
  @Published
  private(set) var state = SoakTestState.idle

  private let source: Source
  private var task: Task<Void, Never>?

  init(source: Source) { self.source = source }

  var isRunning: Bool { state == .running }

  /// The first problem with the entered numbers; nil when they can start a run.
  var problem: SoakTestProblem? {
    if case .failure(let problem) = form.settings() { return problem }
    return nil
  }

  /// Starts a run in the background; a run in progress is not started again.
  func start() {
    guard !isRunning, case .success(let settings) = form.settings() else { return }
    state = .running
    task = Task { @MainActor in
      let row = await check(settings)
      guard !Task.isCancelled else { return }
      state = .finished(ActivityCheckRow(row))
      task = nil
    }
  }

  /// Stops a run in progress and shows the entry again; with no run in progress it does nothing.
  func cancel() {
    guard isRunning else { return }
    task?.cancel()
    task = nil
    state = .idle
  }

  /// Shows the entry again after a result.
  func reset() {
    guard !isRunning else { return }
    state = .idle
  }

  /// The `runtime-health` check: skipped while the service does not run, a failure when sampling
  /// fails.
  private func check(_ settings: SoakTestSettings) async -> DiagnoseCheck {
    let id = "runtime-health"
    let snapshot = await source.snapshot()
    guard snapshot.availability == .running else { return DiagnosticsService.skipped(id, snapshot) }
    guard let processID = await source.processIdentifier() else {
      return DiagnosticsService.skipped(id, snapshot)
    }
    do {
      return DiagnosticsService.soakCheck(try await source.sample(processID, settings))
    } catch {
      return DiagnoseCheck(id, .fail, error.localizedDescription)
    }
  }
}
