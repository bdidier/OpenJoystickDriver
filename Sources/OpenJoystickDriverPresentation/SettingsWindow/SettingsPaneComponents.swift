#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// A titled switch with a one-line description.
  struct SettingsSwitchRow: View {
    let title: String
    let description: String
    let isOn: Binding<Bool>
    var isEnabled = true

    var body: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
          Text(description).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden().disabled(!isEnabled)
          .ojdAccessibilityLabel(title)
      }
    }
  }

  /// The inline error of the preferences model, with the notification permission shortcut.
  struct SettingsErrorBanner: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    var body: some View {
      if let errorMessage = preferences.errorMessage {
        HStack(alignment: .top, spacing: 8) {
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
        }.padding(10).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
      }
    }
  }

  /// The scrolling column every pane lays its groups in.
  struct SettingsPaneColumn<Content: View>: View {
    @ViewBuilder
    let content: Content

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) { content }.padding(24).frame(
          maxWidth: .infinity,
          alignment: .leading
        )
      }
    }
  }

#endif
