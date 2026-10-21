#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The command-line tool link, the Xbox USB driver extension, the developer tools switch and, while it is on, the
  /// developer tools.
  struct AdvancedPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel
    let commandLineTool: CommandLineToolModel
    let developerTools: DeveloperToolsViewModel
    let runtime: RuntimeViewModel

    var body: some View {
      Form {
        SettingsErrorSection(preferences: preferences)
        CommandLineToolSection(commandLineTool: commandLineTool)
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
          DeveloperToolsView(model: developerTools)
        } else {
          Section {
            Text(OJDLocalized.string("settingsPane.advanced.developerToolsOff"))
              .foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        }
      }.ojdGroupedForm()
    }
  }

#endif
