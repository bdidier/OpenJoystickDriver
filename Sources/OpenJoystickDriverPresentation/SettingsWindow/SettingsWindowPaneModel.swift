import Foundation

/// A content size in points, kept free of AppKit so the pane rules can be tested.
struct SettingsPaneSize: Equatable, Sendable {
  let width: Double
  let height: Double
}

extension SettingsWindowPane {
  /// The SF Symbol on the pane's toolbar button.
  var symbolName: String {
    switch self {
    case .general: return "gearshape"
    case .notifications: return "bell"
    case .commandLine: return "terminal"
    case .advanced: return "wrench.and.screwdriver"
    }
  }

  /// Localization key of the pane button's accessibility label.
  var accessibilityKey: String { "a11y.settingsPane.\(rawValue)" }

  /// The content size of the pane; the window is fixed at this size while the pane is shown.
  var minimumContentSize: SettingsPaneSize {
    switch self {
    case .general: return SettingsPaneSize(width: 520, height: 360)
    case .notifications: return SettingsPaneSize(width: 520, height: 380)
    case .commandLine: return SettingsPaneSize(width: 520, height: 240)
    case .advanced: return SettingsPaneSize(width: 760, height: 560)
    }
  }
}

/// Which pane of the Settings window is selected.
@MainActor
final class SettingsWindowPaneModel: ObservableObject {
  let panes = SettingsWindowPane.allCases

  @Published
  private(set) var selected: SettingsWindowPane

  init(selected: SettingsWindowPane = .general) { self.selected = selected }

  /// The window title while the pane is selected.
  var titleKey: String { selected.titleKey }

  var selectedIndex: Int { panes.firstIndex(of: selected) ?? 0 }

  var minimumContentSize: SettingsPaneSize { selected.minimumContentSize }

  func select(_ pane: SettingsWindowPane) { selected = pane }

  /// Selects the pane at a toolbar group position; a position outside the panes selects nothing.
  @discardableResult
  func select(index: Int) -> Bool {
    guard panes.indices.contains(index) else { return false }
    selected = panes[index]
    return true
  }
}
