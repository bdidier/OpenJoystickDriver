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
    /// Why a fix button could not do its action.
    @Published
    var fixFailure: String?
    private let performFix: @MainActor (ActivityCheckFix) -> String?

    /// `performFix` does the action of a fix button and returns why it could not, if it could not.
    init(
      log: ActivityLogModel,
      diagnostics: ActivityDiagnosticsModel,
      performFix: @escaping @MainActor (ActivityCheckFix) -> String?
    ) {
      self.log = log
      self.diagnostics = diagnostics
      self.performFix = performFix
    }

    func perform(_ fix: ActivityCheckFix) { fixFailure = performFix(fix) }
  }

  /// The Activity area: the log table or the diagnostic checks, filling the detail column.
  struct ActivityView: View {
    @ObservedObject
    var model: ActivityModel

    var body: some View {
      switch model.mode {
      case .log: ActivityLogView(model: model.log)
      case .diagnostics:
        ActivityDiagnosticsView(model: model.diagnostics, perform: model.perform).alert(
          isPresented: Binding(
            get: { model.fixFailure != nil },
            set: { if !$0 { model.fixFailure = nil } }
          )
        ) {
          Alert(
            title: Text(model.fixFailure ?? ""),
            dismissButton: .default(Text(OJDLocalized.string("common.ok")))
          )
        }
      }
    }
  }

#endif
