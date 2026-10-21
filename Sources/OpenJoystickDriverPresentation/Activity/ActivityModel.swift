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

/// Whether the Activity log follows the service logs: only while the main window is visible and
/// shows the log.
enum ActivityLogFollowing {
  static func shouldFollow(
    windowVisible: Bool,
    area: MainWindowArea,
    mode: ActivityMode
  ) -> Bool {
    windowVisible && area == .activity && mode == .log
  }
}

/// An action of the Activity area that did not happen: the alert's title and, when there is more
/// to say, its message.
struct ActivityActionFailure: Equatable {
  let title: String
  let message: String?
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
    /// The last action that failed. The alert shows in both views.
    @Published
    var failure: ActivityActionFailure?
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

    func perform(_ fix: ActivityCheckFix) {
      if let title = performFix(fix) { failure = ActivityActionFailure(title: title, message: nil) }
    }
  }

  /// The Activity area: the log table or the diagnostic checks, filling the detail column.
  struct ActivityView: View {
    @ObservedObject
    var model: ActivityModel

    var body: some View {
      content.alert(
        isPresented: Binding(
          get: { model.failure != nil },
          set: { if !$0 { model.failure = nil } }
        )
      ) {
        Alert(
          title: Text(model.failure?.title ?? ""),
          message: model.failure?.message.map { Text($0) },
          dismissButton: .default(Text(OJDLocalized.string("common.ok")))
        )
      }
    }

    @ViewBuilder
    private var content: some View {
      switch model.mode {
      case .log: ActivityLogView(model: model.log)
      case .diagnostics: ActivityDiagnosticsView(model: model.diagnostics, perform: model.perform)
      }
    }
  }

#endif
