#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Xbox USB driver extension, the developer tools switch and, while it is on, the
  /// developer tools.
  struct AdvancedPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel
    let developerTools: DeveloperToolsViewModel
    let runtime: RuntimeViewModel

    var body: some View {
      VStack(spacing: 0) {
        SettingsErrorBanner(preferences: preferences).padding(.horizontal, 24).padding(.top, 12)
        Form {
          DriverExtensionSection(runtime: runtime)
          Section(OJDLocalized.string("settings.developerTools")) {
            SettingsSwitchRow(
              title: OJDLocalized.string("settings.enableDeveloperTools"),
              description: OJDLocalized.string("settings.developerToolsDescription"),
              isOn: Binding(
                get: { preferences.developerToolsEnabled },
                set: { preferences.setDeveloperToolsEnabled($0) }
              )
            )
          }
          if preferences.developerToolsEnabled {
            Section { DeveloperToolsView(model: developerTools) }
          } else {
            Section {
              Text(OJDLocalized.string("settingsPane.advanced.developerToolsOff"))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
          }
        }.ojdGroupedForm()
      }
    }
  }

#endif
