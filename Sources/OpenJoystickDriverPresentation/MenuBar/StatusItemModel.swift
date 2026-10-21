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
  case openProjectWebsite
  case openProblemReport
  case quit
}

/// An entry title: a localization key, or text that comes from data such as a profile name.
enum StatusItemTitle: Equatable {
  case key(String)
  case verbatim(String)
}

/// One row of the status menu. Rows are disabled when they do not apply and are never removed.
struct StatusItemEntry: Equatable {
  let id: String
  let title: StatusItemTitle
  let isEnabled: Bool
  let isChecked: Bool
  /// Nil for the status line, for rows that open a submenu and for separators.
  let action: StatusItemAction?
  let submenu: [Self]?
  let isSeparator: Bool
  /// SF Symbol shown next to the title, if any.
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
  }

  struct Profile: Equatable {
    let id: UUID
    let name: String
    let isActive: Bool
  }

  var statusLine: String
  /// Connected controllers in inventory order. Controller actions apply to the first controller;
  /// Disconnect Wireless Link applies to the first wireless one.
  var controllers: [Controller]
  var profiles: [Profile]
  /// The state glyph shown beside the status line.
  var statusSymbolName: String
}

/// The fixed status-item layout as data.
enum StatusItemModel {
  static let projectWebsite = "https://github.com/xsyetopz/OpenJoystickDriver"
  static let problemReport = "https://github.com/xsyetopz/OpenJoystickDriver/issues/new"

  static func entries(for state: StatusItemState) -> [StatusItemEntry] {
    let target = state.controllers.first
    let wireless = state.controllers.first { $0.isWireless }
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
        title: .key("menuBar.controllers"),
        submenu: controllersSubmenu(target: target, wireless: wireless, profiles: state.profiles)
      ),
      StatusItemEntry(
        id: "profiles",
        title: .key("menuBar.profiles"),
        submenu: [
          StatusItemEntry(
            id: "profiles.activate",
            title: .key("menuBar.activate"),
            isEnabled: state.profiles.contains { !$0.isActive },
            submenu: profileEntries(
              state.profiles.filter { !$0.isActive },
              idPrefix: "profiles.activate",
              action: { .activateProfile($0) },
              checkActive: false
            )
          ),
          StatusItemEntry(
            id: "profiles.deactivate",
            title: .key("menuBar.deactivate"),
            isEnabled: state.profiles.contains { $0.isActive },
            submenu: profileEntries(
              state.profiles.filter { $0.isActive },
              idPrefix: "profiles.deactivate",
              action: { .deactivateProfile($0) },
              checkActive: false
            )
          ),
        ]
      ),
      .separator("separator.profiles"),
      StatusItemEntry(
        id: "grantAccess",
        title: .key("menuBar.grantAccess"),
        action: .showArea(.access),
        symbolName: "lock.shield"
      ),
      StatusItemEntry(
        id: "openWindow",
        title: .key("menuBar.openWindow"),
        action: .openWindow
      ),
      StatusItemEntry(
        id: "settings",
        title: .key("menuBar.settings"),
        action: .showSettings,
        symbolName: "gearshape"
      ),
      .separator("separator.window"),
      StatusItemEntry(id: "help", title: .key("menuBar.help"), submenu: helpSubmenu()),
      .separator("separator.help"),
      StatusItemEntry(id: "quit", title: .key("menuBar.quit"), action: .quit, symbolName: "power"),
    ]
  }

  private static func controllersSubmenu(
    target: StatusItemState.Controller?,
    wireless: StatusItemState.Controller?,
    profiles: [StatusItemState.Profile]
  ) -> [StatusItemEntry] {
    let suspend: StatusItemEntry
    if let target, target.isSuspended {
      suspend = StatusItemEntry(
        id: "controllers.resume",
        title: .key("menuBar.resume"),
        action: .resumeController(sessionToken: target.id)
      )
    } else {
      suspend = StatusItemEntry(
        id: "controllers.suspend",
        title: .key("menuBar.suspend"),
        isEnabled: target != nil,
        action: target.map { .suspendController(sessionToken: $0.id) }
      )
    }
    return [
      suspend,
      StatusItemEntry(
        id: "controllers.testInput",
        title: .key("menuBar.testInput"),
        isEnabled: target != nil,
        action: target.map { .testInput(sessionToken: $0.id) }
      ),
      StatusItemEntry(
        id: "controllers.activeProfile",
        title: .key("menuBar.activeProfile"),
        isEnabled: target != nil && !profiles.isEmpty,
        submenu: profileEntries(
          profiles,
          idPrefix: "controllers.activeProfile",
          action: { .activateProfile($0) },
          checkActive: true
        )
      ),
      StatusItemEntry(
        id: "controllers.disconnectWireless",
        title: .key("menuBar.disconnectWireless"),
        isEnabled: wireless != nil,
        action: wireless.map { .disconnectWireless(sessionToken: $0.id) },
        symbolName: "antenna.radiowaves.left.and.right.slash"
      ),
      StatusItemEntry(
        id: "controllers.showInWindow",
        title: .key("menuBar.showInWindow"),
        isEnabled: target != nil,
        action: target.map { .showController(sessionToken: $0.id) }
      ),
    ]
  }

  private static func profileEntries(
    _ profiles: [StatusItemState.Profile],
    idPrefix: String,
    action: (UUID) -> StatusItemAction,
    checkActive: Bool
  ) -> [StatusItemEntry] {
    profiles.map {
      StatusItemEntry(
        id: "\(idPrefix).\($0.id.uuidString)",
        title: .verbatim($0.name),
        isChecked: checkActive && $0.isActive,
        action: checkActive && $0.isActive ? nil : action($0.id)
      )
    }
  }

  private static func helpSubmenu() -> [StatusItemEntry] {
    [
      StatusItemEntry(
        id: "help.activityLog",
        title: .key("menuBar.activityLog"),
        action: .showArea(.activity)
      ),
      StatusItemEntry(
        id: "help.explainErrorCode",
        title: .key("menuBar.explainErrorCode"),
        action: .showArea(.activity)
      ),
      StatusItemEntry(
        id: "help.reportProblem",
        title: .key("menuBar.reportProblem"),
        action: .openProblemReport
      ),
      StatusItemEntry(
        id: "help.projectWebsite",
        title: .key("menuBar.projectWebsite"),
        action: .openProjectWebsite
      ),
    ]
  }
}

/// The status line: one localized format with positional arguments, so each language orders and
/// punctuates the readiness, controller count and profile as one phrase.
enum StatusItemStatusLine {
  static let formatKey = "menuBar.statusLine"

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
