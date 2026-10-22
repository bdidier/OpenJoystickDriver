import Foundation
import OpenJoystickDriverKit

/// What the app offers beside a check that is not a pass.
enum ActivityCheckFix: Equatable {
  case requestInputRead
  case requestInputInject
  case approveDriver
  case showLibrary

  var titleKey: String {
    switch self {
    case .requestInputRead, .requestInputInject: return "action.request"
    case .approveDriver: return "platform.macos.ui.setup.openSystemSettings"
    case .showLibrary: return "ui.activity.fix.showLibrary"
    }
  }
}

/// A check's place in the app: its name and the GUI action that fixes it. A check without an
/// action says so; its details text still names the fix.
struct ActivityCheckKind: Equatable {
  enum Action: Equatable {
    case fix(ActivityCheckFix)
    case noGUIAction
  }

  let id: String
  let nameKey: String
  let action: Action

  /// Every check of `ojd diagnose` that the app runs. `runtime-health` is a command-line option
  /// and is not run.
  static let all = [
    Self(
      id: "transport-extension-bundle",
      nameKey: "ui.activity.check.transportExtensionBundle",
      action: .noGUIAction
    ),
    Self(
      id: "transport-extension-registration",
      nameKey: "ui.activity.check.transportExtensionRegistration",
      action: .fix(.approveDriver)
    ),
    Self(id: "service", nameKey: "cli.status.group.labelService", action: .noGUIAction),
    Self(
      id: "input-read",
      nameKey: "platform.macos.term.inputRead",
      action: .fix(.requestInputRead)
    ),
    Self(
      id: "input-inject",
      nameKey: "platform.macos.term.inputInject",
      action: .fix(.requestInputInject)
    ),
    Self(
      id: "virtual-device",
      nameKey: "cli.status.group.labelVirtualDevice",
      action: .noGUIAction
    ),
    Self(id: "controller-records", nameKey: "ui.library.records", action: .fix(.showLibrary)),
    Self(id: "config-files", nameKey: "ui.activity.check.configFiles", action: .noGUIAction),
    Self(id: "usb-access", nameKey: "ui.activity.check.usbAccess", action: .fix(.requestInputRead)),
  ]

  static func kind(of id: String) -> Self? { all.first { $0.id == id } }
}

/// One `ojd diagnose` check as a table row. `detail` is the text the command prints; for a
/// check that is not a pass it names the fix.
struct ActivityCheckRow: Identifiable, Equatable {
  let id: String
  let status: DiagnoseStatus
  let detail: String
  /// The localized name; nil for a check the app does not list, which shows its id.
  let nameKey: String?
  /// The button beside a warning or failure whose fix the app can do.
  let fix: ActivityCheckFix?

  init(_ check: DiagnoseCheck) {
    id = check.id
    status = check.status
    detail = check.detail
    let kind = ActivityCheckKind.kind(of: check.id)
    nameKey = kind?.nameKey
    if check.status == .warn || check.status == .fail, case .fix(let fix)? = kind?.action {
      self.fix = fix
    } else {
      fix = nil
    }
  }

  var statusKey: String {
    switch status {
    case .pass: return "ui.activity.status.pass"
    case .warn: return "ui.activity.status.warn"
    case .fail: return "status.failed"
    case .skip: return "ui.activity.status.skip"
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
