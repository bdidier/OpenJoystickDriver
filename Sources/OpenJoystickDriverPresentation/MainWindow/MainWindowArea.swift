import Foundation

/// The five areas of the main window, in sidebar order. `Command-1` to `Command-5` select them
/// in this order. The window opens on Controllers until another area was chosen.
public enum MainWindowArea: String, CaseIterable, Identifiable, Hashable, Sendable {
  case controllers
  case profiles
  case library
  case access
  case activity

  public var id: String { rawValue }

  /// The key equivalent digit that selects this area with `Command`.
  public var keyEquivalent: String {
    switch self {
    case .controllers: return "1"
    case .profiles: return "2"
    case .library: return "3"
    case .access: return "4"
    case .activity: return "5"
    }
  }

  /// SF Symbol of the area's sidebar row, shown before its title.
  public var symbolName: String {
    switch self {
    case .controllers: return "gamecontroller"
    case .profiles: return "slider.horizontal.3"
    case .library: return "books.vertical"
    case .access: return "lock.shield"
    case .activity: return "list.bullet.rectangle"
    }
  }

  /// Localization key of the area's title: its sidebar row, its View menu item and the window
  /// title while it is selected.
  public var titleKey: String { "area.\(rawValue).title" }

  /// Whether the area shows a content list column between the sidebar and its detail.
  public var hasListColumn: Bool {
    switch self {
    case .controllers, .profiles, .library: return true
    case .access, .activity: return false
    }
  }
}

/// The half of a list and detail area that a view renders: the content list column or the
/// detail column.
enum MainWindowColumn {
  case list
  case detail
}

/// Opens the main window on an area. The status item, the main menu and other windows reach
/// the main window only through this.
@preconcurrency
@MainActor
public protocol MainWindowPresenting: AnyObject {
  func showMainWindow(area: MainWindowArea?)
  /// Shows the Explain Error Code sheet over the main window, in the area it is in.
  func showErrorCodeExplainer()
  /// Opens Controllers with the controller selected, for "Show in Window".
  func showController(id: String)
  /// The session token of the controller selected in the Controllers area, if one is connected.
  var selectedControllerID: String? { get }
  /// Opens Controllers > Input Test for the controller.
  func showInputTest(controllerID: String)
  /// Opens Profiles, asks for a profile file and imports it through the editor's checks.
  func importProfile()
  /// Whether a profile of the library is selected in the Profiles screen.
  var hasSelectedProfile: Bool { get }
  /// Opens Profiles, asks where to save the selected profile and writes it.
  func exportProfile()
  /// Opens Library, asks for a record file or mod folder and shows its install confirmation.
  func installRecordOrMod()
}

/// The panes of the Settings window, in toolbar order.
public enum SettingsWindowPane: String, CaseIterable, Identifiable, Hashable, Sendable {
  case general
  case notifications
  case advanced

  public var id: String { rawValue }
  public var titleKey: String { "settingsPane.\(rawValue).title" }
}

@preconcurrency
@MainActor
public protocol SettingsWindowPresenting: AnyObject {
  func showSettings(pane: SettingsWindowPane?)
}
