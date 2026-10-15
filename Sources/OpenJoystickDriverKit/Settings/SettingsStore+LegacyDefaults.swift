import Foundation

extension SettingsStore {
  /// The `UserDefaults` keys that held the settings before `Settings.json` existed.
  enum LegacyDefaultsKey {
    static let launchAtLoginOptOut = "LaunchAtLoginOptOut"
    static let controllerConnected = "OpenJoystickDriver.notifications.controllers"
    static let controllerDisconnected = "OpenJoystickDriver.notifications.controllerDisconnected"
    static let profileActivated = "OpenJoystickDriver.notifications.profiles"
    static let profileDeactivated = "OpenJoystickDriver.notifications.profileDeactivated"
    static let sounds = "OpenJoystickDriver.notifications.sounds"
    static let includePrereleases = "OpenJoystickDriver.updates.includePrereleases"
    static let developerTools = "OpenJoystickDriver.developerTools.enabled"

    static let all = [
      launchAtLoginOptOut, controllerConnected, controllerDisconnected, profileActivated,
      profileDeactivated, sounds, includePrereleases, developerTools,
    ]
  }

  /// Imports the settings an older version kept in `defaults` into the user file, then removes
  /// those keys from `defaults`.
  ///
  /// It does nothing when the user file already exists, so it runs once: the first start after an
  /// upgrade. Without it a user who turned launch at login off would be registered again. A
  /// notification kind that never had its own value followed the older kind (disconnections
  /// followed connections, profile deactivations followed activations), and keeps that value.
  /// When the file cannot be written the keys stay, so the next start tries again.
  public func importLegacyDefaults(from defaults: UserDefaults = .standard) throws {
    guard !FileManager.default.fileExists(atPath: userFileURL.path) else { return }
    func stored(_ key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    var values: [ApplicationSettingKey: Bool] = [:]
    values[.launchAtLogin] = stored(LegacyDefaultsKey.launchAtLoginOptOut).map { !$0 }
    values[.notifyControllerConnected] = stored(LegacyDefaultsKey.controllerConnected)
    values[.notifyControllerDisconnected] =
      stored(LegacyDefaultsKey.controllerDisconnected)
      ?? stored(LegacyDefaultsKey.controllerConnected)
    values[.notifyProfileActivated] = stored(LegacyDefaultsKey.profileActivated)
    values[.notifyProfileDeactivated] =
      stored(LegacyDefaultsKey.profileDeactivated) ?? stored(LegacyDefaultsKey.profileActivated)
    values[.notifySounds] = stored(LegacyDefaultsKey.sounds)
    values[.updatesIncludePrereleases] = stored(LegacyDefaultsKey.includePrereleases)
    values[.developerTools] = stored(LegacyDefaultsKey.developerTools)
    if !values.isEmpty { try update(values) }
    for key in LegacyDefaultsKey.all { defaults.removeObject(forKey: key) }
  }
}
