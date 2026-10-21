#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Launch at login, the menu bar item, the Dock icon and update checks.
  struct GeneralPaneView: View {
    @ObservedObject
    var preferences: SettingsPreferencesModel

    var body: some View {
      Form {
        SettingsErrorSection(preferences: preferences)
        Section {
          SettingsSwitchRow(
            title: OJDLocalized.string("settings.startAtLogin"),
            description: OJDLocalized.string("settings.startAtLoginDescription"),
            isOn: Binding(
              get: { preferences.startAtLogin },
              set: { preferences.setStartAtLogin($0) }
            ),
            isEnabled: preferences.launchAtLoginIsAvailable
          )
          SettingsSwitchRow(
            title: OJDLocalized.string("settingsPane.general.showInMenuBar"),
            description: OJDLocalized.string("settingsPane.general.showInMenuBarDescription"),
            isOn: Binding(
              get: { preferences.showInMenuBar },
              set: { preferences.setShowInMenuBar($0) }
            ),
            isEnabled: !preferences.showInMenuBarIsLocked,
            disabledReason: OJDLocalized.string("settingsPane.general.entryPointRequired")
          )
          SettingsSwitchRow(
            title: OJDLocalized.string("settingsPane.general.showInDock"),
            description: OJDLocalized.string("settingsPane.general.showInDockDescription"),
            isOn: Binding(
              get: { preferences.showInDock },
              set: { preferences.setShowInDock($0) }
            ),
            isEnabled: !preferences.showInDockIsLocked,
            disabledReason: OJDLocalized.string("settingsPane.general.entryPointRequired")
          )
        }
        updates
      }.ojdGroupedForm()
    }

    private var updates: some View {
      Section(OJDLocalized.string("settings.updates")) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              indicator(status.indicator)
              Text(status.title)
            }
            if let latestRelease = status.latestRelease {
              Text(latestRelease).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
          }
          Spacer(minLength: 8)
          Text(status.version).foregroundColor(Color(NSColor.secondaryLabelColor))
          if case .available = preferences.updateState {
            Button(OJDLocalized.string("settings.viewUpdate")) {
              preferences.openAvailableUpdate()
            }
          }
          Button(OJDLocalized.string("settings.checkUpdates")) {
            preferences.checkForUpdates()
          }.disabled(preferences.updateState == .checking)
        }
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
        Toggle(
          OJDLocalized.string("settings.prereleaseUpdates"),
          isOn: Binding(
            get: { preferences.includePrereleaseUpdates },
            set: { preferences.setIncludePrereleaseUpdates($0) }
          )
        )
      }
    }

    @ViewBuilder
    private func indicator(_ indicator: UpdateStatusPresentation.Indicator) -> some View {
      switch indicator {
      case .none: EmptyView()
      case .progress: ProgressView().controlSize(.small).accessibilityHidden(true)
      case .symbol(let name, let tone):
        Image(systemName: name).foregroundColor(Color(Self.color(of: tone)))
          .accessibilityHidden(true)
      }
    }

    private static func color(of tone: UpdateStatusPresentation.Tone) -> NSColor {
      switch tone {
      case .positive: return SemanticState.healthy.presentation.tone.color
      case .attention: return SemanticState.attention.presentation.tone.color
      case .informational: return NSColor.controlAccentColor
      case .failure: return SemanticState.failure.presentation.tone.color
      }
    }

    private var status: UpdateStatusPresentation {
      UpdateStatusPresentation(
        state: preferences.updateState,
        runningVersion: ApplicationVersion.current
      )
    }
  }

#endif
