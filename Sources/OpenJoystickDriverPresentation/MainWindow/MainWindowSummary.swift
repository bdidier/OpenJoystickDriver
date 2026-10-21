import Foundation

/// The line under the area title in the toolbar: what the area holds right now. Areas without
/// such a fact show no line.
enum MainWindowSummary {
  static func text(for area: MainWindowArea, status: RuntimeStatusState) -> String {
    switch area {
    case .controllers:
      guard case .available(let presentation) = status else { return "" }
      return presentation.deviceCountLabel
    case .profiles, .library, .access, .activity: return ""
    }
  }
}
