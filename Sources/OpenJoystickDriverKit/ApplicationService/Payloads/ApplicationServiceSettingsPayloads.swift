import Foundation

/// An app setting the service can read and apply; each raw value is the stable key that
/// `ojd setting` takes and that names the setting in `Settings.json`.
public enum ApplicationSettingKey: String, Codable, CaseIterable, Sendable {
  case launchAtLogin
  case showInMenuBar
  case showInDock
  case notifyControllerConnected = "notify.controllerConnected"
  case notifyControllerDisconnected = "notify.controllerDisconnected"
  case notifyProfileActivated = "notify.profileActivated"
  case notifyProfileDeactivated = "notify.profileDeactivated"
  case notifySounds = "notify.sounds"
  case updatesCheckAutomatically = "updates.checkAutomatically"
  case updatesIncludePrereleases = "updates.includePrereleases"
  case developerTools

  /// The value while no settings file stores one: true for `showInMenuBar` and `notify.sounds`,
  /// false otherwise (`showInDock` included).
  public var defaultValue: Bool { self == .showInMenuBar || self == .notifySounds }
}

/// One app setting and its current value.
public struct ApplicationSettingValue: Codable, Equatable, Sendable {
  public let key: ApplicationSettingKey
  public let value: Bool

  public init(key: ApplicationSettingKey, value: Bool) {
    self.key = key
    self.value = value
  }
}

/// The result of `getSettings` and `setSetting`: every setting, in `ApplicationSettingKey` order.
public struct ApplicationSettingsPayload: Codable, Equatable, Sendable {
  public let settings: [ApplicationSettingValue]

  public init(settings: [ApplicationSettingValue]) { self.settings = settings }

  public func value(of key: ApplicationSettingKey) -> Bool? {
    settings.first { $0.key == key }?.value
  }
}

/// Arguments of `setSetting`.
public struct ApplicationServiceSettingArguments: Codable, Sendable {
  public let key: ApplicationSettingKey
  public let value: Bool

  public init(key: ApplicationSettingKey, value: Bool) {
    self.key = key
    self.value = value
  }
}
