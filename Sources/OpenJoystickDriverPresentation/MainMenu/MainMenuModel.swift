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
  case saveSupportReport
  case saveActivityLog

  case undo
  case redo
  case cut
  case copy
  case paste
  case selectAll

  case showArea(MainWindowArea)
  case toggleSidebar
  case toggleFullScreen

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
  case copySupportReport
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
  /// Exactly one controller is connected, so the Controller and Profile menus have a target.
  case controller
  case wirelessController
  case controllerHasActiveProfile
  case profileExists
  /// A profile is selected in the Profiles screen.
  case profileSelected
}

/// How an item decides whether it is enabled.
enum MainMenuEnabledRule: Hashable, Sendable {
  /// AppKit validates the item against the responder chain.
  case responderChain
  /// The item is enabled when every requirement holds.
  case requires(Set<MainMenuRequirement>)

  static let always = Self.requires([])
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
  var profileCount = 0
  var hasSelectedProfile = false
  var hasMainWindow = false
  var hasSettingsWindow = false
  var isSidebarVisible = true
  var isFullScreen = false

  /// The controller the Controller and Profile menus act on: the only connected one. With
  /// several, the menus cannot tell which is meant, so those items stay disabled and Show in
  /// Window opens Controllers.
  var controller: MainMenuControllerState? { controllers.count == 1 ? controllers[0] : nil }

  func satisfies(_ requirement: MainMenuRequirement) -> Bool {
    switch requirement {
    case .mainWindow: return hasMainWindow
    case .settingsWindow: return hasSettingsWindow
    case .controller: return controller != nil
    case .wirelessController: return controller?.isWireless == true
    case .controllerHasActiveProfile: return controller?.hasActiveProfile == true
    case .profileExists: return profileCount > 0
    case .profileSelected: return hasSelectedProfile
    }
  }
}

/// The main menu as data: titles, key equivalents, actions, enabled rules and GUI counterparts.
/// The test checks this; ``MainMenuRenderer`` renders it to an `NSMenu`.
enum MainMenuModel {
  static let sections: [MainMenuSection] = [
    appSection, fileSection, editSection, viewSection, controllerSection, profileSection,
    windowSection, helpSection,
  ]

  static var allItems: [MainMenuItem] { sections.flatMap(\.items) }

  static func item(for action: MainMenuAction) -> MainMenuItem? {
    allItems.first { $0.action == action }
  }

  static func isEnabled(_ item: MainMenuItem, state: MainMenuState) -> Bool {
    switch item.enabled {
    case .responderChain: return true
    case .requires(let requirements): return requirements.allSatisfy(state.satisfies)
    }
  }

  /// The title key to show: the alternate one for Hide Sidebar, Exit Full Screen and Resume.
  static func titleKey(of item: MainMenuItem, state: MainMenuState) -> String {
    guard let alternate = item.alternateTitleKey else { return item.titleKey }
    switch item.action {
    case .toggleSidebar: return state.isSidebarVisible ? alternate : item.titleKey
    case .toggleFullScreen: return state.isFullScreen ? alternate : item.titleKey
    case .suspendOrResumeController:
      return state.controller?.isSuspended == true ? alternate : item.titleKey
    default: return item.titleKey
    }
  }

  private static func entry(
    _ id: String,
    _ titleKey: String,
    alternate: String? = nil,
    key: String = "",
    modifiers: MainMenuModifiers = [.command],
    action: MainMenuAction,
    enabled: MainMenuEnabledRule = .always,
    gui: MainMenuGUICounterpart
  ) -> MainMenuEntry {
    .item(
      MainMenuItem(
        id: id,
        titleKey: titleKey,
        alternateTitleKey: alternate,
        keyEquivalent: key,
        modifiers: key.isEmpty ? [] : modifiers,
        action: action,
        enabled: enabled,
        guiCounterpart: gui
      )
    )
  }

  private static let needsMainWindow = MainMenuEnabledRule.requires([.mainWindow])

  private static let appSection = MainMenuSection(
    id: "app",
    titleKey: "app.name",
    entries: [
      entry("about", "mainMenu.app.about", action: .about, gui: .standardCommand),
      .separator,
      entry(
        "settings",
        "mainMenu.app.settings",
        key: ",",
        action: .settings,
        enabled: .requires([.settingsWindow]),
        gui: .settingsPane(.general)
      ),
      .separator,
      entry(
        "services",
        "mainMenu.app.services",
        action: .services,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "hide",
        "mainMenu.app.hide",
        key: "h",
        action: .hide,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "hideOthers",
        "mainMenu.app.hideOthers",
        key: "h",
        modifiers: [.command, .option],
        action: .hideOthers,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "showAll",
        "mainMenu.app.showAll",
        action: .showAll,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry("quit", "mainMenu.app.quit", key: "q", action: .quit, gui: .standardCommand),
    ]
  )

  private static let fileSection = MainMenuSection(
    id: "file",
    titleKey: "mainMenu.file",
    entries: [
      entry(
        "importProfile",
        "mainMenu.file.importProfile",
        key: "o",
        action: .importProfile,
        enabled: needsMainWindow,
        gui: .area(.profiles)
      ),
      entry(
        "exportProfile",
        "mainMenu.file.exportProfile",
        key: "e",
        modifiers: [.command, .shift],
        action: .exportProfile,
        enabled: .requires([.mainWindow, .profileSelected]),
        gui: .area(.profiles)
      ),
      .separator,
      entry(
        "installRecordOrMod",
        "mainMenu.file.installRecordOrMod",
        action: .installRecordOrMod,
        enabled: needsMainWindow,
        gui: .area(.library)
      ),
      .separator,
      entry(
        "saveSupportReport",
        "mainMenu.file.saveSupportReport",
        action: .saveSupportReport,
        gui: .area(.activity)
      ),
      entry(
        "saveActivityLog",
        "mainMenu.file.saveActivityLog",
        action: .saveActivityLog,
        gui: .area(.activity)
      ),
    ]
  )

  private static let editSection = MainMenuSection(
    id: "edit",
    titleKey: "mainMenu.edit",
    entries: [
      entry(
        "undo",
        "mainMenu.edit.undo",
        key: "z",
        action: .undo,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "redo",
        "mainMenu.edit.redo",
        key: "z",
        modifiers: [.command, .shift],
        action: .redo,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "cut",
        "mainMenu.edit.cut",
        key: "x",
        action: .cut,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "copy",
        "mainMenu.edit.copy",
        key: "c",
        action: .copy,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "paste",
        "mainMenu.edit.paste",
        key: "v",
        action: .paste,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "selectAll",
        "mainMenu.edit.selectAll",
        key: "a",
        action: .selectAll,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  private static let viewSection = MainMenuSection(
    id: "view",
    titleKey: "mainMenu.view",
    entries: MainWindowArea.allCases.map { area in
      entry(
        "showArea.\(area.rawValue)",
        area.titleKey,
        key: area.keyEquivalent,
        action: .showArea(area),
        enabled: needsMainWindow,
        gui: .area(area)
      )
    } + [
      .separator,
      entry(
        "toggleSidebar",
        "mainMenu.view.showSidebar",
        alternate: "mainMenu.view.hideSidebar",
        key: "s",
        modifiers: [.command, .control],
        action: .toggleSidebar,
        enabled: .responderChain,
        gui: .sidebarToolbarButton
      ),
      entry(
        "toggleFullScreen",
        "mainMenu.view.enterFullScreen",
        alternate: "mainMenu.view.exitFullScreen",
        key: "f",
        modifiers: [.command, .control],
        action: .toggleFullScreen,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  private static let controllerSection = MainMenuSection(
    id: "controller",
    titleKey: "mainMenu.controller",
    entries: [
      entry(
        "suspendOrResume",
        "mainMenu.controller.suspend",
        alternate: "mainMenu.controller.resume",
        action: .suspendOrResumeController,
        enabled: .requires([.controller]),
        gui: .area(.controllers)
      ),
      entry(
        "testInput",
        "mainMenu.controller.testInput",
        action: .testInput,
        enabled: .requires([.controller, .mainWindow]),
        gui: .area(.controllers)
      ),
      entry(
        "disconnectWirelessLink",
        "mainMenu.controller.disconnectWirelessLink",
        action: .disconnectWirelessLink,
        enabled: .requires([.controller, .wirelessController]),
        gui: .area(.controllers)
      ),
      .separator,
      entry(
        "showControllerInWindow",
        "mainMenu.controller.showInWindow",
        action: .showControllerInWindow,
        enabled: .requires([.mainWindow]),
        gui: .area(.controllers)
      ),
    ]
  )

  private static let profileSection = MainMenuSection(
    id: "profile",
    titleKey: "mainMenu.profile",
    entries: [
      entry(
        "activateProfile",
        "mainMenu.profile.activate",
        action: .activateProfile,
        enabled: .requires([.profileExists]),
        gui: .area(.profiles)
      ),
      entry(
        "deactivateProfile",
        "mainMenu.profile.deactivate",
        action: .deactivateProfile,
        enabled: .requires([.controller, .controllerHasActiveProfile]),
        gui: .area(.profiles)
      ),
    ]
  )

  private static let windowSection = MainMenuSection(
    id: "window",
    titleKey: "mainMenu.window",
    entries: [
      entry(
        "minimize",
        "mainMenu.window.minimize",
        key: "m",
        action: .minimize,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "zoom",
        "mainMenu.window.zoom",
        action: .zoom,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "bringAllToFront",
        "mainMenu.window.bringAllToFront",
        action: .bringAllToFront,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  private static let helpSection = MainMenuSection(
    id: "help",
    titleKey: "mainMenu.help",
    entries: [
      entry(
        "showActivityLog",
        "mainMenu.help.activityLog",
        action: .showActivityLog,
        enabled: needsMainWindow,
        gui: .area(.activity)
      ),
      entry(
        "copySupportReport",
        "mainMenu.help.copySupportReport",
        action: .copySupportReport,
        gui: .area(.activity)
      ),
      .separator,
      entry(
        "openProjectWebsite",
        "mainMenu.help.projectWebsite",
        action: .openProjectWebsite,
        gui: .externalLink
      ),
    ]
  )
}
