#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Per-event notifications, the notification permission and Send Test Notification.
  struct NotificationsPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    var body: some View {
      Form {
        SettingsErrorSection(preferences: preferences)
        Section(OJDLocalized.string("ui.settings.general.controllers")) {
          eventToggle(
            "ui.settings.notifications.controllerConnectedShort",
            "ui.settings.notifications.controllerNotifications",
            \.controllerNotifications,
            preferences.setControllerNotifications
          )
          eventToggle(
            "ui.settings.notifications.controllerDisconnectedShort",
            "ui.settings.notifications.controllerDisconnectedNotifications",
            \.controllerDisconnectedNotifications,
            preferences.setControllerDisconnectedNotifications
          )
        }
        Section(OJDLocalized.string("ui.settings.general.profiles")) {
          eventToggle(
            "ui.settings.notifications.profileActivatedShort",
            "ui.settings.notifications.profileNotifications",
            \.profileNotifications,
            preferences.setProfileNotifications
          )
          eventToggle(
            "ui.settings.notifications.profileDeactivatedShort",
            "ui.settings.notifications.profileDeactivatedNotifications",
            \.profileDeactivatedNotifications,
            preferences.setProfileDeactivatedNotifications
          )
        }
        Section {
          Toggle(
            OJDLocalized.string("ui.settings.notifications.notificationSounds"),
            isOn: Binding(
              get: { preferences.notificationSounds },
              set: { preferences.setNotificationSounds($0) }
            )
          )
        }
        Section { deliveryRow }
      }.ojdGroupedForm()
    }

    private var deliveryRow: some View {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(deliveryStatus).foregroundColor(
          deliveryNeedsAttention
            ? Color(NSColor.systemOrange) : Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 12)
        if deliveryNeedsAttention {
          Button(OJDLocalized.string("ui.settings.general.openNotificationSettings")) {
            preferences.openNotificationSettings()
          }
        }
        Button(OJDLocalized.string("ui.settings.notifications.testNotification")) {
          preferences.sendTestNotification()
        }
      }
    }

    private func eventToggle(
      _ titleKey: String,
      _ accessibilityKey: String,
      _ value: KeyPath<SettingsPreferencesModel, Bool>,
      _ set: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> some View {
      Toggle(
        OJDLocalized.string(titleKey),
        isOn: Binding(get: { preferences[keyPath: value] }, set: set)
      ).ojdAccessibilityLabel(OJDLocalized.string(accessibilityKey))
    }

    private var deliveryNeedsAttention: Bool {
      guard preferences.notificationAuthorization == .allowed else { return false }
      return preferences.notificationSystemSettings.alertStyle == .none
        || preferences.notificationSystemSettings.soundsEnabled == false
    }

    private var deliveryStatus: String {
      guard preferences.notificationAuthorization == .allowed else {
        return OJDLocalized.string("ui.settings.notifications.notificationPermissionRequired")
      }
      switch (
        preferences.notificationSystemSettings.alertStyle,
        preferences.notificationSystemSettings.soundsEnabled
      ) {
      case (.none, false):
        return OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationBannersAndSoundOff"
        )
      case (.none, _):
        return OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationBannersOffDetail"
        )
      case (_, false):
        return OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationSoundOffDetail"
        )
      case (.banner, true), (.alert, true):
        return OJDLocalized.string("ui.settings.notifications.notificationDeliveryReady")
      case (.unknown, _), (_, nil):
        return OJDLocalized.string("ui.settings.notifications.notificationDeliveryAllowed")
      }
    }
  }

#endif
