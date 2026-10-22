import Foundation
import OpenJoystickDriverKit

/// What one status-item entry does when chosen. AppKit renders entries; the coordinator performs
/// actions.
enum StatusItemAction: Equatable {
  case suspendController(sessionToken: String)
  case resumeController(sessionToken: String)
  case testInput(sessionToken: String)
  case disconnectWireless(sessionToken: String)
  case showController(sessionToken: String)
  case activateProfile(UUID)
  case deactivateProfile(UUID)
  case showArea(MainWindowArea)
  /// Opens the main window on the area it last showed.
  case openWindow
  case showSettings
  /// Shows the Explain Error Code sheet.
  case explainErrorCode
  case openProjectWebsite
  case openProblemReport
  case quit
}

/// An entry title: a localization key, or text that comes from data such as a profile name.
enum StatusItemTitle: Equatable {
  case key(String)
  case verbatim(String)
}

/// One row of the status menu. Controller and profile rows are disabled when they do not apply.
struct StatusItemEntry: Equatable {
  let id: String
  let title: StatusItemTitle
  let isEnabled: Bool
  let isChecked: Bool
  /// Nil for the status line, for rows that open a submenu and for separators.
  let action: StatusItemAction?
  let submenu: [Self]?
  let isSeparator: Bool
  /// SF Symbol shown next to the title, if any. Only the status line has one: the HIG gives every
  /// item of a group an icon or none, and the other groups have none.
  let symbolName: String?

  init(
    id: String,
    title: StatusItemTitle,
    isEnabled: Bool = true,
    isChecked: Bool = false,
    action: StatusItemAction? = nil,
    submenu: [Self]? = nil,
    symbolName: String? = nil
  ) {
    self.id = id
    self.title = title
    self.isEnabled = isEnabled
    self.isChecked = isChecked
    self.action = action
    self.submenu = submenu
    self.isSeparator = false
    self.symbolName = symbolName
  }

  private init(separatorID: String) {
    self.id = separatorID
    self.title = .verbatim("")
    self.isEnabled = false
    self.isChecked = false
    self.action = nil
    self.submenu = nil
    self.isSeparator = true
    self.symbolName = nil
  }

  static func separator(_ id: String) -> Self { Self(separatorID: id) }
}

/// What the status menu needs to know about the service state.
struct StatusItemState: Equatable {
  struct Controller: Equatable {
    /// The session token of the attachment.
    let id: String
    let name: String
    let isSuspended: Bool
    /// Whether the controller is linked over Bluetooth, from the typed transport.
    let isWireless: Bool
    /// The profiles that apply to this controller (same model, and its unit when a profile names
    /// one). ``Profile/isActive`` tells whether the profile is the one active for it.
    var profiles: [Profile] = []
  }

  struct Profile: Equatable {
    let id: UUID
    let name: String
    let isActive: Bool
  }

  var statusLine: String
  /// Whether a required permission or access is missing.
  var needsAccess: Bool
  /// Connected controllers in inventory order. Each has its own actions; Disconnect Wireless
  /// Link is enabled only for a wireless one.
  var controllers: [Controller]
  var profiles: [Profile]
  /// Whether the service reported the profile list. An empty list claims that no profile exists
  /// only when it was reported.
  var profileListRead: Bool
  /// The state glyph shown beside the status line.
  var statusSymbolName: String
}

/// The fixed status-item layout as data.
enum StatusItemModel {
  static let projectWebsite = "https://github.com/xsyetopz/OpenJoystickDriver"
  static let problemReport = "https://github.com/xsyetopz/OpenJoystickDriver/issues/new"

  static func entries(for state: StatusItemState) -> [StatusItemEntry] {
    let grantAccess =
      state.needsAccess
      ? [
        StatusItemEntry(
          id: "grantAccess",
          title: .key("ui.extra.grantAccess"),
          action: .showArea(.access)
        )
      ] : []
    return [
      StatusItemEntry(
        id: "status",
        title: .verbatim(state.statusLine),
        isEnabled: false,
        symbolName: state.statusSymbolName
      ),
      .separator("separator.status"),
      StatusItemEntry(
        id: "controllers",
        title: .key("ui.extra.controllers"),
        submenu: controllersSubmenu(
          controllers: state.controllers,
          profileListRead: state.profileListRead
        )
      ),
      StatusItemEntry(
        id: "profiles",
        title: .key("ui.extra.profiles"),
        submenu: [
          StatusItemEntry(
            id: "profiles.activate",
            title: .key("ui.extra.activate"),
            submenu: profileEntries(
              state.profiles,
              idPrefix: "profiles.activate",
              action: { .activateProfile($0) },
              checkActive: true,
              emptyTitleKey: MainMenuModel.emptyActivateProfileTitleKey(
                profileListRead: state.profileListRead
              )
            )
          ),
          StatusItemEntry(
            id: "profiles.deactivate",
            title: .key("ui.extra.deactivate"),
            submenu: profileEntries(
              state.profiles.filter(\.isActive),
              idPrefix: "profiles.deactivate",
              action: { .deactivateProfile($0) },
              checkActive: false,
              emptyTitleKey: MainMenuModel.emptyDeactivateProfileTitleKey(
                profileListRead: state.profileListRead
              )
            )
          ),
        ]
      ),
      .separator("separator.profiles"),
    ] + grantAccess + [
      StatusItemEntry(
        id: "openWindow",
        title: .key("ui.extra.openWindow"),
        action: .openWindow
      ),
      StatusItemEntry(
        id: "settings",
        title: .key("ui.menu.app.settings"),
        action: .showSettings
      ),
      .separator("separator.window"),
      StatusItemEntry(id: "help", title: .key("ui.extra.help"), submenu: helpSubmenu()),
      .separator("separator.help"),
      StatusItemEntry(id: "quit", title: .key("ui.menu.app.quit"), action: .quit),
    ]
  }

  /// One submenu per connected controller, each with that controller's own actions. With no
  /// controller connected the submenu holds one disabled row that says so.
  private static func controllersSubmenu(
    controllers: [StatusItemState.Controller],
    profileListRead: Bool
  ) -> [StatusItemEntry] {
    guard !controllers.isEmpty else {
      return [
        StatusItemEntry(
          id: "controllers.none",
          title: .key(MainMenuModel.noControllerTitleKey),
          isEnabled: false
        )
      ]
    }
    return controllers.map { controller in
      StatusItemEntry(
        id: "controllers.\(controller.id)",
        title: .verbatim(controller.name),
        submenu: controllerActions(controller, profileListRead: profileListRead)
      )
    }
  }

  private static func controllerActions(
    _ controller: StatusItemState.Controller,
    profileListRead: Bool
  ) -> [StatusItemEntry] {
    let prefix = "controllers.\(controller.id)"
    let suspend: StatusItemEntry
    if controller.isSuspended {
      suspend = StatusItemEntry(
        id: "\(prefix).resume",
        title: .key("ui.extra.resume"),
        action: .resumeController(sessionToken: controller.id)
      )
    } else {
      suspend = StatusItemEntry(
        id: "\(prefix).suspend",
        title: .key("ui.extra.suspend"),
        action: .suspendController(sessionToken: controller.id)
      )
    }
    return [
      suspend,
      StatusItemEntry(
        id: "\(prefix).testInput",
        title: .key("ui.extra.testInput"),
        action: .testInput(sessionToken: controller.id)
      ),
      StatusItemEntry(
        id: "\(prefix).activeProfile",
        title: .key("ui.extra.activeProfile"),
        submenu: profileEntries(
          controller.profiles,
          idPrefix: "\(prefix).activeProfile",
          action: { .activateProfile($0) },
          checkActive: true,
          emptyTitleKey: MainMenuModel.emptyActivateProfileTitleKey(
            profileListRead: profileListRead
          )
        )
      ),
      StatusItemEntry(
        id: "\(prefix).disconnectWireless",
        title: .key("ui.extra.disconnectWireless"),
        isEnabled: controller.isWireless,
        action: controller.isWireless ? .disconnectWireless(sessionToken: controller.id) : nil
      ),
      StatusItemEntry(
        id: "\(prefix).showInWindow",
        title: .key("ui.extra.showInWindow"),
        action: .showController(sessionToken: controller.id)
      ),
    ]
  }

  /// The profile rows of a submenu. A submenu stays enabled when it holds no profile: it then
  /// holds one disabled row that says why (HIG, Menus). With `checkActive`, the active profile
  /// shows a checkmark and cannot be chosen again.
  private static func profileEntries(
    _ profiles: [StatusItemState.Profile],
    idPrefix: String,
    action: (UUID) -> StatusItemAction,
    checkActive: Bool,
    emptyTitleKey: String
  ) -> [StatusItemEntry] {
    guard !profiles.isEmpty else {
      return [
        StatusItemEntry(
          id: "\(idPrefix).none",
          title: .key(emptyTitleKey),
          isEnabled: false
        )
      ]
    }
    return profiles.map {
      let isChosen = checkActive && $0.isActive
      return StatusItemEntry(
        id: "\(idPrefix).\($0.id.uuidString)",
        title: .verbatim($0.name),
        isEnabled: !isChosen,
        isChecked: isChosen,
        action: isChosen ? nil : action($0.id)
      )
    }
  }

  private static func helpSubmenu() -> [StatusItemEntry] {
    [
      StatusItemEntry(
        id: "help.activityLog",
        title: .key("ui.extra.activityLog"),
        action: .showArea(.activity)
      ),
      StatusItemEntry(
        id: "help.explainErrorCode",
        title: .key("ui.extra.explainErrorCode"),
        action: .explainErrorCode
      ),
      StatusItemEntry(
        id: "help.reportProblem",
        title: .key("ui.extra.reportProblem"),
        action: .openProblemReport
      ),
      StatusItemEntry(
        id: "help.projectWebsite",
        title: .key("ui.extra.projectWebsite"),
        action: .openProjectWebsite
      ),
    ]
  }
}

/// The status line: one localized format with positional arguments, so each language orders and
/// punctuates the readiness, controller count and profile as one phrase.
enum StatusItemStatusLine {
  static let formatKey = "ui.extra.statusLine"

  static func make(
    readiness: String,
    controllers: String,
    profile: String,
    localization: Localization,
    locale: Locale
  ) -> String {
    localization.formatted(
      formatKey,
      locale: locale,
      arguments: [readiness, controllers, profile]
    )
  }
}
