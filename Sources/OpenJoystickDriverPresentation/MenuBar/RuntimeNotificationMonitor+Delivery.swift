#if canImport(AppKit)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UserNotifications

  extension RuntimeNotificationMonitor {

    func observe(_ snapshot: RuntimeNotificationSnapshot) {
      guard let previousSnapshot else {
        self.previousSnapshot = snapshot
        return
      }
      self.previousSnapshot = snapshot
      for event in RuntimeNotificationDiff.events(from: previousSnapshot, to: snapshot) {
        deliver(event)
      }
    }

    func deliver(_ event: RuntimeNotificationEvent) {
      switch event {
      case .controllerConnected(let name):
        guard preferenceIsEnabled(.notifyControllerConnected) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerConnected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerConnectedBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .controllerDisconnected(let name):
        guard preferenceIsEnabled(.notifyControllerDisconnected) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerDisconnected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerDisconnectedBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .activeProfileChanged(let previousName, let currentName):
        let preferenceKey: ApplicationSettingKey =
          currentName == nil ? .notifyProfileDeactivated : .notifyProfileActivated
        guard preferenceIsEnabled(preferenceKey) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.profileChanged"
          ),
          body: profileChangeBody(from: previousName, to: currentName),
          sound: notificationSoundIsEnabled
        )
      case .controllerNeedsAttention(let name):
        guard preferenceIsEnabled(.notifyControllerConnected) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerNeedsAttention"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerNeedsAttentionBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      }
    }

    private var notificationSoundIsEnabled: Bool { preferenceIsEnabled(.notifySounds) }

    /// A settings file that cannot be read is logged with its path, and the built-in default of
    /// the key applies, so sounds keep their true default.
    private func preferenceIsEnabled(_ key: ApplicationSettingKey) -> Bool {
      do { return try settings.value(of: key) } catch {
        let message =
          "[Settings] \(settings.userFileURL.path) cannot be read, using the default for "
          + "\(key.rawValue): \(error.localizedDescription)\n"
        FileHandle.standardError.write(Data(message.utf8))
        return key.defaultValue
      }
    }

    private func profileChangeBody(from previousName: String?, to currentName: String?) -> String {
      switch (previousName, currentName) {
      case (.some(let previous), .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileSwitchedBody",
          previous,
          current
        )
      case (.none, .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileActivatedBody",
          current
        )
      case (.some(let previous), .none):
        return OJDLocalized.formatted(
          "notifications.profileDeactivatedBody",
          previous
        )
      case (.none, .none):
        return OJDLocalized.string("status.noActiveProfile")
      }
    }
  }

#endif
