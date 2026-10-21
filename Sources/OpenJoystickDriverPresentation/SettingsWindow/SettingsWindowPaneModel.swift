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
    case .advanced: return "wrench.and.screwdriver"
    }
  }

  /// Localization key of the pane button's accessibility label.
  var accessibilityKey: String { "a11y.settingsPane.\(rawValue)" }

  /// The toolbar item identifier of the pane's button.
  var toolbarItemIdentifier: String { "OpenJoystickDriver.SettingsPane.\(rawValue)" }

  /// The pane whose toolbar button has the identifier; nil for any other identifier.
  init?(toolbarItemIdentifier: String) {
    let matching = Self.allCases.filter { $0.toolbarItemIdentifier == toolbarItemIdentifier }
    guard let pane = matching.first else { return nil }
    self = pane
  }

  /// The width that fits the toolbar buttons of every pane and the packet table of Advanced.
  static let contentWidth = 600.0

  /// The shortest content area a pane gets.
  static let minimumContentHeight = 100.0

  /// The content size of a pane whose content is `fittingHeight` tall: every pane has the same
  /// width, and a pane taller than `availableHeight` gets that height and scrolls.
  static func contentSize(fittingHeight: Double, availableHeight: Double) -> SettingsPaneSize {
    let height = max(min(fittingHeight, availableHeight), minimumContentHeight)
    return SettingsPaneSize(width: contentWidth, height: height)
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

  func select(_ pane: SettingsWindowPane) { selected = pane }

  /// Selects the pane at a toolbar group position; a position outside the panes selects nothing.
  @discardableResult
  func select(index: Int) -> Bool {
    guard panes.indices.contains(index) else { return false }
    selected = panes[index]
    return true
  }
}
