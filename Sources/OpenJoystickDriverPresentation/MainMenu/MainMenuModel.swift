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
    if state.controllers.isEmpty { return .key("ui.controllers.emptyTitle") }
    return .key("ui.menu.controller.noneSelected")
  }

  /// The title key to show: the alternate one for Hide Sidebar, Exit Full Screen and Resume.
  static func titleKey(of item: MainMenuItem, state: MainMenuState) -> String {
    guard let alternate = item.alternateTitleKey else { return item.titleKey }
    switch item.action {
    case .toggleToolbar: return state.isToolbarVisible ? alternate : item.titleKey
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
    titleKey: "term.app.name",
    entries: [
      entry("about", "ui.menu.app.about", action: .about, gui: .standardCommand),
      .separator,
      entry(
        "settings",
        "ui.menu.app.settings",
        key: ",",
        action: .settings,
        enabled: .requires([.settingsWindow]),
        gui: .settingsPane(.general)
      ),
      .separator,
      entry(
        "services",
        "ui.menu.app.services",
        action: .services,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "hide",
        "ui.menu.app.hide",
        key: "h",
        action: .hide,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "hideOthers",
        "ui.menu.app.hideOthers",
        key: "h",
        modifiers: [.command, .option],
        action: .hideOthers,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "showAll",
        "ui.menu.app.showAll",
        action: .showAll,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry("quit", "ui.menu.app.quit", key: "q", action: .quit, gui: .standardCommand),
    ]
  )

  private static let fileSection = MainMenuSection(
    id: "file",
    titleKey: "ui.menu.file.title",
    entries: [
      entry(
        "importProfile",
        "ui.menu.file.importProfile",
        key: "o",
        action: .importProfile,
        enabled: needsMainWindow,
        gui: .area(.profiles)
      ),
      entry(
        "exportProfile",
        "ui.menu.file.exportProfile",
        key: "e",
        modifiers: [.command, .shift],
        action: .exportProfile,
        enabled: .requires([.mainWindow, .profileSelected]),
        gui: .area(.profiles)
      ),
      .separator,
      entry(
        "installRecordOrMod",
        "ui.menu.file.installRecordOrMod",
        action: .installRecordOrMod,
        enabled: needsMainWindow,
        gui: .area(.library)
      ),
      .separator,
      entry(
        "close",
        "ui.menu.file.close",
        key: "w",
        action: .close,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "saveSupportReport",
        "ui.menu.file.saveSupportReport",
        action: .saveSupportReport,
        gui: .area(.activity)
      ),
      entry(
        "saveActivityLog",
        "ui.menu.file.saveActivityLog",
        action: .saveActivityLog,
        gui: .area(.activity)
      ),
    ]
  )

  private static let editSection = MainMenuSection(
    id: "edit",
    titleKey: "ui.menu.edit.title",
    entries: [
      entry(
        "undo",
        "ui.menu.edit.undo",
        key: "z",
        action: .undo,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "redo",
        "ui.menu.edit.redo",
        key: "z",
        modifiers: [.command, .shift],
        action: .redo,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "cut",
        "ui.menu.edit.cut",
        key: "x",
        action: .cut,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "copy",
        "ui.menu.edit.copy",
        key: "c",
        action: .copy,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "paste",
        "ui.menu.edit.paste",
        key: "v",
        action: .paste,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "delete",
        "action.delete",
        action: .delete,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "selectAll",
        "ui.menu.edit.selectAll",
        key: "a",
        action: .selectAll,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  private static let viewSection = MainMenuSection(
    id: "view",
    titleKey: "ui.menu.view.title",
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
        "toggleToolbar",
        "ui.menu.view.showToolbar",
        alternate: "ui.menu.view.hideToolbar",
        key: "t",
        modifiers: [.command, .option],
        action: .toggleToolbar,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "toggleSidebar",
        "ui.menu.view.showSidebar",
        alternate: "ui.menu.view.hideSidebar",
        key: "s",
        modifiers: [.command, .control],
        action: .toggleSidebar,
        enabled: .responderChain,
        gui: .sidebarToolbarButton
      ),
      .separator,
      entry(
        "toggleFullScreen",
        "ui.menu.view.enterFullScreen",
        alternate: "ui.menu.view.exitFullScreen",
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
    titleKey: "ui.menu.controller.title",
    entries: [
      entry(
        "controllerTarget",
        "ui.controllers.emptyTitle",
        action: .controllerTarget,
        enabled: .never,
        gui: .area(.controllers)
      ),
      .separator,
      entry(
        "suspendOrResume",
        "ui.menu.controller.suspend",
        alternate: "ui.menu.controller.resume",
        action: .suspendOrResumeController,
        enabled: .requires([.controller]),
        gui: .area(.controllers)
      ),
      entry(
        "testInput",
        "ui.menu.controller.testInput",
        action: .testInput,
        enabled: .requires([.controller, .mainWindow]),
        gui: .area(.controllers)
      ),
      entry(
        "disconnectWirelessLink",
        "ui.menu.controller.disconnectWirelessLink",
        action: .disconnectWirelessLink,
        enabled: .requires([.controller, .wirelessController]),
        gui: .area(.controllers)
      ),
      .separator,
      entry(
        "showControllerInWindow",
        "ui.menu.controller.showInWindow",
        action: .showControllerInWindow,
        enabled: .requires([.mainWindow]),
        gui: .area(.controllers)
      ),
    ]
  )

  private static let profileSection = MainMenuSection(
    id: "profile",
    titleKey: "ui.menu.profile.title",
    entries: [
      entry(
        "activateProfile",
        "ui.menu.profile.activate",
        action: .activateProfile,
        enabled: .always,
        gui: .area(.profiles)
      ),
      entry(
        "deactivateProfile",
        "ui.menu.profile.deactivate",
        action: .deactivateProfile,
        enabled: .requires([.controller, .controllerHasActiveProfile]),
        gui: .area(.profiles)
      ),
    ]
  )

  private static let windowSection = MainMenuSection(
    id: "window",
    titleKey: "ui.menu.window.title",
    entries: [
      entry(
        "minimize",
        "ui.menu.window.minimize",
        key: "m",
        action: .minimize,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "zoom",
        "ui.menu.window.zoom",
        action: .zoom,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "bringAllToFront",
        "ui.menu.window.bringAllToFront",
        action: .bringAllToFront,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  private static let helpSection = MainMenuSection(
    id: "help",
    titleKey: "ui.menu.help.title",
    entries: [
      entry(
        "showActivityLog",
        "ui.menu.help.activityLog",
        action: .showActivityLog,
        enabled: needsMainWindow,
        gui: .area(.activity)
      ),
      entry(
        "explainErrorCode",
        "ui.menu.help.explainErrorCode",
        action: .explainErrorCode,
        enabled: needsMainWindow,
        gui: .area(.activity)
      ),
      entry(
        "copySupportReport",
        "ui.menu.help.copySupportReport",
        action: .copySupportReport,
        gui: .area(.activity)
      ),
      .separator,
      entry(
        "reportProblem",
        "ui.menu.help.reportProblem",
        action: .reportProblem,
        gui: .externalLink
      ),
      entry(
        "openProjectWebsite",
        "ui.menu.help.projectWebsite",
        action: .openProjectWebsite,
        gui: .externalLink
      ),
    ]
  )
}
