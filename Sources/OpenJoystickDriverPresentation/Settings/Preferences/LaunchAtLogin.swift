#if canImport(AppKit)

  import Foundation
  import OpenJoystickDriverKit

  protocol LaunchAtLoginControlling {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
  }

  /// The macOS login item; the choice is recorded in the settings files, as `ojd setting` does.
  struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    let settings: SettingsStore

    init(settings: SettingsStore = SettingsStore()) { self.settings = settings }

    var isAvailable: Bool {
      if #available(macOS 13.0, *) { return true }
      return false
    }

    var isEnabled: Bool { ApplicationServiceManager.isLaunchAtLoginEnabled }

    func setEnabled(_ enabled: Bool) throws {
      if enabled {
        try ApplicationServiceManager.install(settings: settings)
      } else {
        try ApplicationServiceManager.uninstall(settings: settings)
      }
    }
  }

#endif
