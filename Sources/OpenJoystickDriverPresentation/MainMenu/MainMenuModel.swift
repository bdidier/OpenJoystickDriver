import Foundation

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

  /// The text of the controller target row: the selected controller's name; the key that says no
  /// controller is connected; or, when controllers are connected but none is selected (or the
  /// selected one is gone), the key that says no controller is selected.
  static func controllerTargetTitle(state: MainMenuState) -> StatusItemTitle {
    if let controller = state.controller { return .verbatim(controller.name) }
    if state.controllers.isEmpty { return .key("controllers.emptyTitle") }
    return .key("mainMenu.controller.noneSelected")
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
        "close",
        "mainMenu.file.close",
        key: "w",
        action: .close,
        enabled: .responderChain,
        gui: .standardCommand
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
        "delete",
        "common.delete",
        action: .delete,
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
        "controllerTarget",
        "controllers.emptyTitle",
        action: .controllerTarget,
        enabled: .never,
        gui: .area(.controllers)
      ),
      .separator,
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
        "explainErrorCode",
        "mainMenu.help.explainErrorCode",
        action: .explainErrorCode,
        enabled: needsMainWindow,
        gui: .area(.activity)
      ),
      entry(
        "copySupportReport",
        "mainMenu.help.copySupportReport",
        action: .copySupportReport,
        gui: .area(.activity)
      ),
      entry(
        "reportProblem",
        "mainMenu.help.reportProblem",
        action: .reportProblem,
        gui: .externalLink
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
