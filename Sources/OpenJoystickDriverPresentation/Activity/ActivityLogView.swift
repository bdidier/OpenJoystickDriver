#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// A full-height table of the service log lines. The toolbar holds the filter, the search and
  /// the actions.
  struct ActivityLogView: View {
    @ObservedObject
    var model: ActivityLogModel

    var body: some View {
      content.onAppear { model.start() }.onDisappear { model.stop() }.alert(
        isPresented: Binding(
          get: { model.actionFailure != nil },
          set: { if !$0 { model.actionFailure = nil } }
        )
      ) {
        Alert(
          title: Text(OJDLocalized.string("mainMenu.file.saveFailed")),
          message: Text(model.actionFailure ?? ""),
          dismissButton: .default(Text(OJDLocalized.string("common.ok")))
        )
      }
    }

    @ViewBuilder
    private var content: some View {
      if let failure = model.loadFailure {
        ServiceFailureStateView(
          title: OJDLocalized.string("console.loadError"),
          message: failure,
          retry: model.start
        ).padding()
      } else if model.rows.isEmpty {
        Text(OJDLocalized.string("console.empty")).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(model.rows) {
          TableColumn(OJDLocalized.string("console.stream")) { row in
            Text(OJDLocalized.string(row.stream.activityTitleKey))
          }.width(min: 60, ideal: 70, max: 90)
          TableColumn(OJDLocalized.string("activity.column.message")) { row in
            Text(row.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
          }
        }
      }
    }
  }

#endif
