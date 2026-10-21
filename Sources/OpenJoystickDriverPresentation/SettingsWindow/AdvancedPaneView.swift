#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The developer tools switch and, while it is on, the developer tools.
  struct AdvancedPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel
    let developerTools: DeveloperToolsViewModel

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          GroupBox {
            SettingsSwitchRow(
              title: OJDLocalized.string("settings.enableDeveloperTools"),
              description: OJDLocalized.string("settings.developerToolsDescription"),
              isOn: Binding(
                get: { preferences.developerToolsEnabled },
                set: { preferences.setDeveloperToolsEnabled($0) }
              )
            ).padding(4)
          } label: {
            Text(OJDLocalized.string("settings.developerTools")).font(.headline)
          }
          SettingsErrorBanner(preferences: preferences)
        }.padding(24)
        if preferences.developerToolsEnabled {
          DeveloperToolsView(model: developerTools)
        } else {
          Text(OJDLocalized.string("settingsPane.advanced.developerToolsOff")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          ).padding(.horizontal, 24)
          Spacer(minLength: 0)
        }
      }
    }
  }

#endif
