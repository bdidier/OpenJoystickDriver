import Foundation

/// Modifier keys of a menu key equivalent, independent of AppKit.
struct MainMenuModifiers: OptionSet, Hashable, Sendable {
  let rawValue: UInt8

  static let command = Self(rawValue: 1 << 0)
  static let shift = Self(rawValue: 1 << 1)
  static let option = Self(rawValue: 1 << 2)
  static let control = Self(rawValue: 1 << 3)
}

/// What choosing a main menu item does. The renderer maps each case to a responder-chain
/// selector or to the coordinator; the compiler checks the mapping is exhaustive.
enum MainMenuAction: Hashable, Sendable {
  case about
  case settings
  case services
  case hide
  case hideOthers
  case showAll
  case quit

  case importProfile
  case exportProfile
  case installRecordOrMod
  case close
  case saveSupportReport
  case saveActivityLog

  case undo
  case redo
  case cut
  case copy
  case paste
  case delete
  case selectAll

  case showArea(MainWindowArea)
  case toggleSidebar
  case toggleFullScreen

  /// A disabled row that names the controller the menu acts on, or says there is none.
  case controllerTarget
  case suspendOrResumeController
  case testInput
  case disconnectWirelessLink
  case showControllerInWindow

  case activateProfile
  case deactivateProfile

  case minimize
  case zoom
  case bringAllToFront

  case showActivityLog
  case explainErrorCode
  case copySupportReport
  case reportProblem
  case openProjectWebsite
}

extension MainMenuAction {
  /// Whether the action runs a flow of its own (a file panel, a profile choice) instead of
  /// only showing an area.
  var performsFlow: Bool {
    switch self {
    case .importProfile, .exportProfile, .activateProfile, .installRecordOrMod: return true
    default: return false
    }
  }
}

/// A condition on the app state that must hold for an item to be enabled.
enum MainMenuRequirement: Hashable, Sendable {
  case mainWindow
  case settingsWindow
  /// A controller is selected in the Controllers area, so the Controller and Profile menus have
  /// a target.
  case controller
  case wirelessController
  case controllerHasActiveProfile
  case profileExists
  /// A profile is selected in the Profiles screen.
  case profileSelected
  /// Never holds; keeps an informational item disabled.
  case unavailable
}

/// How an item decides whether it is enabled.
enum MainMenuEnabledRule: Hashable, Sendable {
  /// AppKit validates the item against the responder chain.
  case responderChain
  /// The item is enabled when every requirement holds.
  case requires(Set<MainMenuRequirement>)

  static let always = Self.requires([])
  /// The item only shows information and is never enabled.
  static let never = Self.requires([.unavailable])
}

/// The place in the GUI that offers the same function as a menu item. The menu bar is a subset
/// of the GUI, so every item has one.
enum MainMenuGUICounterpart: Hashable, Sendable {
  case area(MainWindowArea)
  case settingsPane(SettingsWindowPane)
  /// The sidebar button in the main window toolbar.
  case sidebarToolbarButton
  /// A standard window control or a system-wide macOS command.
  case standardCommand
  /// A link that opens in the default browser.
  case externalLink
}

struct MainMenuItem: Equatable, Sendable {
  let id: String
  let titleKey: String
  /// Localization key of the title while the item's alternate state holds; see
  /// ``MainMenuModel/titleKey(of:state:)``.
  let alternateTitleKey: String?
  let keyEquivalent: String
  let modifiers: MainMenuModifiers
  let action: MainMenuAction
  let enabled: MainMenuEnabledRule
  let guiCounterpart: MainMenuGUICounterpart
}

enum MainMenuEntry: Equatable, Sendable {
  case item(MainMenuItem)
  case separator

  var item: MainMenuItem? {
    if case .item(let item) = self { return item }
    return nil
  }
}

struct MainMenuSection: Equatable, Sendable {
  let id: String
  let titleKey: String
  let entries: [MainMenuEntry]

  var items: [MainMenuItem] { entries.compactMap(\.item) }
}

/// What the menu needs to know about one connected controller.
struct MainMenuControllerState: Equatable, Sendable {
  let id: String
  let name: String
  let isSuspended: Bool
  let isWireless: Bool
  let hasActiveProfile: Bool
}

/// The app state that enables items and picks their titles.
struct MainMenuState: Equatable, Sendable {
  var controllers: [MainMenuControllerState] = []
  /// The session token of the controller selected in the Controllers area.
  var selectedControllerID: String?
  var profileCount = 0
  var hasSelectedProfile = false
  var hasMainWindow = false
  var hasSettingsWindow = false
  var isFullScreen = false
  var isSidebarVisible = true

  /// The controller the Controller and Profile menus act on: the one selected in the Controllers
  /// area. Without a target those items stay disabled and the Controller menu's first row says
  /// whether no controller is connected or none is selected.
  var controller: MainMenuControllerState? {
    guard let selectedControllerID else { return nil }
    return controllers.first { $0.id == selectedControllerID }
  }

  func satisfies(_ requirement: MainMenuRequirement) -> Bool {
    switch requirement {
    case .mainWindow: return hasMainWindow
    case .settingsWindow: return hasSettingsWindow
    case .controller: return controller != nil
    case .wirelessController: return controller?.isWireless == true
    case .controllerHasActiveProfile: return controller?.hasActiveProfile == true
    case .profileExists: return profileCount > 0
    case .profileSelected: return hasSelectedProfile
    case .unavailable: return false
    }
  }
}
