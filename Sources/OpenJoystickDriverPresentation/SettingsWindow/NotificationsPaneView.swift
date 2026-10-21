#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Per-event notifications, the notification permission and Send Test Notification.
  struct NotificationsPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    var body: some View {
      SettingsPaneColumn {
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
              eventGroup(
                title: OJDLocalized.string("settings.controllers"),
                first: eventToggle(
                  "settings.controllerConnectedShort",
                  "settings.controllerNotifications",
                  \.controllerNotifications,
                  preferences.setControllerNotifications
                ),
                second: eventToggle(
                  "settings.controllerDisconnectedShort",
                  "settings.controllerDisconnectedNotifications",
                  \.controllerDisconnectedNotifications,
                  preferences.setControllerDisconnectedNotifications
                )
              )
              eventGroup(
                title: OJDLocalized.string("settings.profiles"),
                first: eventToggle(
                  "settings.profileActivatedShort",
                  "settings.profileNotifications",
                  \.profileNotifications,
                  preferences.setProfileNotifications
                ),
                second: eventToggle(
                  "settings.profileDeactivatedShort",
                  "settings.profileDeactivatedNotifications",
                  \.profileDeactivatedNotifications,
                  preferences.setProfileDeactivatedNotifications
                )
              )
              Spacer(minLength: 0)
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(OJDLocalized.string("settings.notificationSounds"))
                Text(deliveryStatus).font(.caption).foregroundColor(
                  deliveryNeedsAttention
                    ? Color(NSColor.systemOrange) : Color(NSColor.secondaryLabelColor)
                )
                if deliveryNeedsAttention {
                  Button(OJDLocalized.string("settings.openNotificationSettings")) {
                    preferences.openNotificationSettings()
                  }
                }
              }
              Spacer(minLength: 12)
              Toggle(
                OJDLocalized.string("settings.notificationSounds"),
                isOn: Binding(
                  get: { preferences.notificationSounds },
                  set: { preferences.setNotificationSounds($0) }
                )
              ).toggleStyle(.switch).labelsHidden().ojdAccessibilityLabel(
                OJDLocalized.string("settings.notificationSounds")
              )
              Button(OJDLocalized.string("settings.testNotification")) {
                preferences.sendTestNotification()
              }
            }
          }.padding(4).frame(maxWidth: .infinity, alignment: .topLeading)
        } label: {
          Text(OJDLocalized.string("settings.notifications")).font(.headline)
        }
        SettingsErrorBanner(preferences: preferences)
      }.onAppear { preferences.refreshNotificationAuthorization() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in preferences.refreshNotificationAuthorization() }
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
      ).toggleStyle(.checkbox).ojdAccessibilityLabel(OJDLocalized.string(accessibilityKey))
    }

    private func eventGroup(title: String, first: some View, second: some View) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        first
        second
      }.frame(maxWidth: .infinity, alignment: .leading)
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
