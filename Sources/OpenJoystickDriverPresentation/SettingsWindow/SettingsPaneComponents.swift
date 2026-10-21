#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// A titled switch with a one-line description below it; while the switch is disabled and has
  /// a `disabledReason`, the reason replaces the description.
  struct SettingsSwitchRow: View {
    let title: String
    let description: String
    let isOn: Binding<Bool>
    var isEnabled = true
    var disabledReason: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Toggle(title, isOn: isOn).disabled(!isEnabled)
        Text(isEnabled ? description : disabledReason ?? description).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The inline error of the preferences model as a form section, with the notification
  /// permission shortcut; it is empty while there is no error.
  struct SettingsErrorSection: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    var body: some View {
      if let errorMessage = preferences.errorMessage {
        Section {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            OJDSystemSymbol(
              name: SemanticState.attention.presentation.symbolName,
              fallback: OJDLocalized.string("common.needsAttention")
            ).foregroundColor(Color(SemanticState.attention.presentation.tone.color))
            Text(errorMessage).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if preferences.notificationAuthorization == .denied {
              Button(OJDLocalized.string("settings.openSystemSettings")) {
                preferences.openNotificationSettings()
              }
            }
            Button(OJDLocalized.string("common.dismiss")) { preferences.dismissError() }
          }
        }
      }
    }
  }

#endif
