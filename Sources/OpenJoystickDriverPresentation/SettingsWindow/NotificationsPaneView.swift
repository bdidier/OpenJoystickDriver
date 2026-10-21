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
        Section(OJDLocalized.string("settings.controllers")) {
          eventToggle(
            "settings.controllerConnectedShort",
            "settings.controllerNotifications",
            \.controllerNotifications,
            preferences.setControllerNotifications
          )
          eventToggle(
            "settings.controllerDisconnectedShort",
            "settings.controllerDisconnectedNotifications",
            \.controllerDisconnectedNotifications,
            preferences.setControllerDisconnectedNotifications
          )
        }
        Section(OJDLocalized.string("settings.profiles")) {
          eventToggle(
            "settings.profileActivatedShort",
            "settings.profileNotifications",
            \.profileNotifications,
            preferences.setProfileNotifications
          )
          eventToggle(
            "settings.profileDeactivatedShort",
            "settings.profileDeactivatedNotifications",
            \.profileDeactivatedNotifications,
            preferences.setProfileDeactivatedNotifications
          )
        }
        Section {
          Toggle(
            OJDLocalized.string("settings.notificationSounds"),
            isOn: Binding(
              get: { preferences.notificationSounds },
              set: { preferences.setNotificationSounds($0) }
            )
          )
        }
        Section { deliveryRow }
      }.ojdGroupedForm().onAppear { preferences.refreshNotificationAuthorization() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in preferences.refreshNotificationAuthorization() }
    }

    private var deliveryRow: some View {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(deliveryStatus).foregroundColor(
          deliveryNeedsAttention
            ? Color(NSColor.systemOrange) : Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 12)
        if deliveryNeedsAttention {
          Button(OJDLocalized.string("settings.openNotificationSettings")) {
            preferences.openNotificationSettings()
          }
        }
        Button(OJDLocalized.string("settings.testNotification")) {
          preferences.sendTestNotification()
        }
      }
    }

    private func eventToggle(
      _ titleKey: String,
      _ accessibilityKey: String,
      _ value: KeyPath<SettingsPreferencesModel, Bool>,
      _ set: @escaping (Bool) -> Void
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
        return OJDLocalized.string("settings.notificationPermissionRequired")
      }
      switch (
        preferences.notificationSystemSettings.alertStyle,
        preferences.notificationSystemSettings.soundsEnabled
      ) {
      case (.none, false): return OJDLocalized.string("settings.notificationBannersAndSoundOff")
      case (.none, _): return OJDLocalized.string("settings.notificationBannersOffDetail")
      case (_, false): return OJDLocalized.string("settings.notificationSoundOffDetail")
      case (.banner, true), (.alert, true):
        return OJDLocalized.string("settings.notificationDeliveryReady")
      case (.unknown, _), (_, nil):
        return OJDLocalized.string("settings.notificationDeliveryAllowed")
      }
    }
  }

#endif
