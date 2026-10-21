import Foundation

/// The two views of the Activity area; the toolbar's segmented control switches them.
enum ActivityMode: Int, CaseIterable {
  case log
  case diagnostics

  var titleKey: String {
    switch self {
    case .log: return "activity.mode.log"
    case .diagnostics: return "activity.mode.diagnostics"
    }
  }
}

#if canImport(AppKit) && canImport(SwiftUI)

  import SwiftUI

  /// The state of the Activity area: which view it shows, the log and the diagnostic checks.
  @MainActor
  final class ActivityModel: ObservableObject {
    @Published
    var mode = ActivityMode.log
    let log: ActivityLogModel
    let diagnostics: ActivityDiagnosticsModel

    init(log: ActivityLogModel, diagnostics: ActivityDiagnosticsModel) {
      self.log = log
      self.diagnostics = diagnostics
    }
  }

  /// The Activity area: the log table or the diagnostic checks, filling the detail column.
  struct ActivityView: View {
    @ObservedObject
    var model: ActivityModel

    var body: some View {
      switch model.mode {
      case .log: ActivityLogView(model: model.log)
      case .diagnostics: ActivityDiagnosticsView(model: model.diagnostics)
      }
    }
  }

#endif
