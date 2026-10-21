import Foundation

/// The six areas of the main window, in toolbar and sidebar order.
/// `Command-1` to `Command-6` select them in this order.
public enum MainWindowArea: String, CaseIterable, Identifiable, Hashable, Sendable {
  case status
  case controllers
  case profiles
  case library
  case access
  case activity

  public var id: String { rawValue }

  /// The key equivalent digit that selects this area with `Command`.
  public var keyEquivalent: String {
    switch self {
    case .status: return "1"
    case .controllers: return "2"
    case .profiles: return "3"
    case .library: return "4"
    case .access: return "5"
    case .activity: return "6"
    }
  }

  /// Localization key of the area's title, also the window title while it is selected.
  public var titleKey: String { "area.\(rawValue).title" }

  /// Localization key of the area's accessibility label.
  public var accessibilityKey: String { "a11y.area.\(rawValue)" }

  public var symbolName: String {
    switch self {
    case .status: return "gauge"
    case .controllers: return "gamecontroller"
    case .profiles: return "slider.horizontal.3"
    case .library: return "books.vertical"
    case .access: return "lock.shield"
    case .activity: return "list.bullet.rectangle"
    }
  }
}

/// Opens the main window on an area. The status item, the main menu and other windows reach
/// the main window only through this.
@preconcurrency
@MainActor
public protocol MainWindowPresenting: AnyObject {
  func showMainWindow(area: MainWindowArea?)
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
  case commandLine
  case advanced

  public var id: String { rawValue }
  public var titleKey: String { "settingsPane.\(rawValue).title" }
}

@preconcurrency
@MainActor
public protocol SettingsWindowPresenting: AnyObject {
  func showSettings(pane: SettingsWindowPane?)
}
