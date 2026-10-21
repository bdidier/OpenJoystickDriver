#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Launch at login, the menu bar item and update checks.
  struct GeneralPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    var body: some View {
      SettingsPaneColumn {
        GroupBox {
          VStack(alignment: .leading, spacing: 14) {
            SettingsSwitchRow(
              title: OJDLocalized.string("settings.startAtLogin"),
              description: OJDLocalized.string("settings.startAtLoginDescription"),
              isOn: Binding(
                get: { preferences.startAtLogin },
                set: { preferences.setStartAtLogin($0) }
              ),
              isEnabled: preferences.launchAtLoginIsAvailable
            )
            Divider()
            SettingsSwitchRow(
              title: OJDLocalized.string("settingsPane.general.showInMenuBar"),
              description: OJDLocalized.string("settingsPane.general.showInMenuBarDescription"),
              isOn: Binding(
                get: { preferences.showInMenuBar },
                set: { preferences.setShowInMenuBar($0) }
              )
            )
          }.padding(4).frame(maxWidth: .infinity, alignment: .topLeading)
        } label: {
          Text(OJDLocalized.string("settings.general")).font(.headline)
        }
        updates
        SettingsErrorBanner(preferences: preferences)
      }
    }

    private var updates: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(updateStatusTitle).font(.body.weight(.medium))
              Text(updateStatusDetail).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
            Spacer()
            if case .available = preferences.updateState {
              Button(OJDLocalized.string("settings.viewUpdate")) {
                preferences.openAvailableUpdate()
              }
            }
            Button(OJDLocalized.string("settings.checkUpdates")) {
              preferences.checkForUpdates()
            }.disabled(preferences.updateState == .checking)
          }
          Divider()
          SettingsSwitchRow(
            title: OJDLocalized.string("settingsPane.general.checkUpdatesAutomatically"),
            description: OJDLocalized.string(
              "settingsPane.general.checkUpdatesAutomaticallyDescription"
            ),
            isOn: Binding(
              get: { preferences.checkUpdatesAutomatically },
              set: { preferences.setCheckUpdatesAutomatically($0) }
            )
          )
          Divider()
          HStack {
            Text(OJDLocalized.string("settings.prereleaseUpdates"))
            Spacer(minLength: 12)
            Toggle(
              OJDLocalized.string("settings.prereleaseUpdates"),
              isOn: Binding(
                get: { preferences.includePrereleaseUpdates },
                set: { preferences.setIncludePrereleaseUpdates($0) }
              )
            ).toggleStyle(.switch).labelsHidden().ojdAccessibilityLabel(
              OJDLocalized.string("settings.prereleaseUpdates")
            )
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("settings.updates")).font(.headline)
      }
    }

    private var updateStatusTitle: String {
      switch preferences.updateState {
      case .idle: return OJDLocalized.string("settings.updateIdle")
      case .checking: return OJDLocalized.string("settings.updateChecking")
      case .upToDate: return OJDLocalized.string("settings.upToDate")
      case .available: return OJDLocalized.string("settings.updateAvailable")
      case .failed: return OJDLocalized.string("settings.updateFailed")
      }
    }

    private var updateStatusDetail: String {
      switch preferences.updateState {
      case .idle:
        return OJDLocalized.formatted("settings.currentVersion", ApplicationVersion.current)
      case .checking: return OJDLocalized.string("settings.contactingGitHub")
      case .upToDate(let tag): return tag
      case .available(let info): return info.tagName
      case .failed(let failure): return failure.message
      }
    }
  }

#endif
