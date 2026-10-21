#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit

  /// The menus ``MainMenuRenderer`` built, with the ones AppKit tracks by role.
  struct RenderedMainMenu {
    let menu: NSMenu
    let servicesMenu: NSMenu
    let windowMenu: NSMenu
    let helpMenu: NSMenu
  }

  /// Renders ``MainMenuModel`` to an `NSMenu`. Items that act through the responder chain keep a
  /// nil target; every other item targets the coordinator, which performs the action by item id.
  @MainActor
  enum MainMenuRenderer {
    static func render(target: MenuBarCoordinator) -> RenderedMainMenu {
      let appName = OJDLocalized.string("app.name")
      let menu = NSMenu(title: appName)
      let servicesMenu = NSMenu(title: OJDLocalized.string("mainMenu.app.services"))
      var windowMenu: NSMenu?
      var helpMenu: NSMenu?
      for section in MainMenuModel.sections {
        let submenu = NSMenu(title: title(section.titleKey, appName: appName))
        submenu.delegate = target
        for entry in section.entries {
          switch entry {
          case .separator: submenu.addItem(.separator())
          case .item(let item):
            submenu.addItem(
              makeItem(item, appName: appName, target: target, servicesMenu: servicesMenu)
            )
          }
        }
        let sectionItem = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        sectionItem.submenu = submenu
        menu.addItem(sectionItem)
        if section.id == "window" { windowMenu = submenu }
        if section.id == "help" { helpMenu = submenu }
      }
      guard let windowMenu, let helpMenu else {
        preconditionFailure("The main menu model has no Window or Help section")
      }
      return RenderedMainMenu(
        menu: menu,
        servicesMenu: servicesMenu,
        windowMenu: windowMenu,
        helpMenu: helpMenu
      )
    }

    /// The text of a title that is a localization key or data such as a controller name.
    static func text(of title: StatusItemTitle) -> String {
      switch title {
      case .key(let key): return OJDLocalized.string(key)
      case .verbatim(let text): return text
      }
    }

    static func title(_ key: String, appName: String) -> String {
      let text = OJDLocalized.string(key)
      return text.contains("%@") ? String(format: text, appName) : text
    }

    private static func makeItem(
      _ item: MainMenuItem,
      appName: String,
      target: MenuBarCoordinator,
      servicesMenu: NSMenu
    ) -> NSMenuItem {
      let menuItem = NSMenuItem(
        title: title(item.titleKey, appName: appName),
        action: nil,
        keyEquivalent: item.keyEquivalent
      )
      menuItem.identifier = NSUserInterfaceItemIdentifier(item.id)
      menuItem.keyEquivalentModifierMask = modifierMask(item.modifiers)
      switch routing(for: item.action) {
      case .services:
        menuItem.submenu = servicesMenu
      case .profileSubmenu:
        let profiles = NSMenu(title: menuItem.title)
        profiles.delegate = target
        menuItem.submenu = profiles
      case .responder(let selector):
        menuItem.action = selector
      case .informational:
        break
      case .coordinator:
        menuItem.action = #selector(MenuBarCoordinator.performMainMenuItem(_:))
        menuItem.target = target
      }
      return menuItem
    }

    /// How a menu item is attached: submenu parents carry no action, so the coordinator never
    /// receives an action that only has a submenu.
    enum Routing {
      case services
      case profileSubmenu
      case responder(Selector)
      case coordinator
      /// A row that shows text and has no action.
      case informational
    }

    static func routing(for action: MainMenuAction) -> Routing {
      if action == .services { return .services }
      if action == .activateProfile { return .profileSubmenu }
      if action == .controllerTarget { return .informational }
      if let selector = responderSelector(for: action) { return .responder(selector) }
      return .coordinator
    }

    static func modifierMask(_ modifiers: MainMenuModifiers) -> NSEvent.ModifierFlags {
      var mask: NSEvent.ModifierFlags = []
      if modifiers.contains(.command) { mask.insert(.command) }
      if modifiers.contains(.shift) { mask.insert(.shift) }
      if modifiers.contains(.option) { mask.insert(.option) }
      if modifiers.contains(.control) { mask.insert(.control) }
      return mask
    }

    /// The selector sent down the responder chain, or nil when the coordinator performs the
    /// action. `.services` is a submenu and has no selector.
    static func responderSelector(for action: MainMenuAction) -> Selector? {
      switch action {
      case .undo: return Selector(("undo:"))
      case .redo: return Selector(("redo:"))
      case .cut: return #selector(NSText.cut(_:))
      case .copy: return #selector(NSText.copy(_:))
      case .paste: return #selector(NSText.paste(_:))
      case .delete: return #selector(NSText.delete(_:))
      case .selectAll: return #selector(NSText.selectAll(_:))
      case .close: return #selector(NSWindow.performClose(_:))
      case .hide: return #selector(NSApplication.hide(_:))
      case .hideOthers: return #selector(NSApplication.hideOtherApplications(_:))
      case .showAll: return #selector(NSApplication.unhideAllApplications(_:))
      case .toggleToolbar: return #selector(NSWindow.toggleToolbarShown(_:))
      case .toggleSidebar: return #selector(NSSplitViewController.toggleSidebar(_:))
      case .toggleFullScreen: return #selector(NSWindow.toggleFullScreen(_:))
      case .minimize: return #selector(NSWindow.performMiniaturize(_:))
      case .zoom: return #selector(NSWindow.performZoom(_:))
      case .bringAllToFront: return #selector(NSApplication.arrangeInFront(_:))
      case .services, .about, .settings, .quit, .importProfile, .exportProfile,
        .installRecordOrMod, .saveSupportReport, .saveActivityLog, .showArea,
        .controllerTarget, .suspendOrResumeController, .testInput, .disconnectWirelessLink,
        .showControllerInWindow, .activateProfile, .deactivateProfile, .showActivityLog,
        .explainErrorCode, .copySupportReport, .reportProblem, .openProjectWebsite:
        return nil
      }
    }
  }

#endif
