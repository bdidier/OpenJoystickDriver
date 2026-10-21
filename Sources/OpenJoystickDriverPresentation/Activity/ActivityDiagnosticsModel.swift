import Foundation
import OpenJoystickDriverKit

/// One `ojd diagnose` check as a table row. A check that is not a pass names its fix in
/// `detail`, as the command prints it.
struct ActivityCheckRow: Identifiable, Equatable {
  let id: String
  let status: DiagnoseStatus
  let detail: String

  init(_ check: DiagnoseCheck) {
    id = check.id
    status = check.status
    detail = check.detail
  }

  var statusKey: String {
    switch status {
    case .pass: return "activity.status.pass"
    case .warn: return "activity.status.warn"
    case .fail: return "common.failed"
    case .skip: return "activity.status.skip"
    }
  }

  var symbolName: String {
    switch status {
    case .pass: return "checkmark.circle.fill"
    case .warn: return "exclamationmark.triangle.fill"
    case .fail: return "xmark.octagon.fill"
    case .skip: return "minus.circle"
    }
  }
}

/// The result of running the checks of `ojd diagnose`.
enum ActivityDiagnosticsState: Equatable {
  case idle
  case running
  case finished([ActivityCheckRow])
}

/// Runs the checks of `ojd diagnose` for the Activity Diagnostics view.
@MainActor
final class ActivityDiagnosticsModel: ObservableObject {
  @Published
  private(set) var state = ActivityDiagnosticsState.idle

  private let runChecks: @MainActor () async -> [DiagnoseCheck]

  init(runChecks: @escaping @MainActor () async -> [DiagnoseCheck]) { self.runChecks = runChecks }

  var isRunning: Bool { state == .running }

  /// Runs every check once; a run in progress is not started again.
  func run() async {
    guard !isRunning else { return }
    state = .running
    state = .finished(await runChecks().map(ActivityCheckRow.init))
  }

  /// Runs the checks when none ran yet.
  func runIfNeeded() async {
    guard state == .idle else { return }
    await run()
  }
}
