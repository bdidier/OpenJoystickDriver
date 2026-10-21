#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The `ojd diagnose` checks as a table: each check with its result and, when it is not a
  /// pass, the fix.
  struct ActivityDiagnosticsView: View {
    @ObservedObject
    var model: ActivityDiagnosticsModel

    var body: some View {
      content.task { await model.runIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
      switch model.state {
      case .idle, .running: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .finished(let rows):
        Table(rows) {
          TableColumn(OJDLocalized.string("common.status")) { row in
            Label {
              Text(OJDLocalized.string(row.statusKey))
            } icon: {
              Image(systemName: row.symbolName).foregroundColor(Self.color(of: row.status))
            }
          }.width(min: 90, ideal: 110, max: 140)
          TableColumn(OJDLocalized.string("activity.column.check")) { row in Text(row.id) }
            .width(min: 140, ideal: 200)
          TableColumn(OJDLocalized.string("activity.column.details")) { row in
            Text(row.detail).textSelection(.enabled)
          }
        }
      }
    }

    private static func color(of status: DiagnoseStatus) -> Color {
      switch status {
      case .pass: return Color(NSColor.systemGreen)
      case .warn: return Color(NSColor.systemOrange)
      case .fail: return Color(NSColor.systemRed)
      case .skip: return Color(NSColor.secondaryLabelColor)
      }
    }
  }

#endif
