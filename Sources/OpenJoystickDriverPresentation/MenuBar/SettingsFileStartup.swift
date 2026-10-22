#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  /// What the app does at launch about a settings file that cannot be used.
  ///
  /// While the settings file can't be read, the menu bar item shows, whatever Show in menu bar
  /// would say, and an alert offers Reset Settings, Show in Finder, and Quit.
  enum SettingsFileStartup: Equatable {
    case proceed
    case offerRecovery(SettingsStoreError)

    static func decide(settingsError: SettingsStoreError?) -> Self {
      settingsError.map(Self.offerRecovery) ?? .proceed
    }

    /// The menu bar item is the one entry point the app is sure to have, so it shows while the
    /// settings file can't be read and the Show in menu bar value is only the default.
    static func statusItemIsShown(showInMenuBar: Bool, settingsError: SettingsStoreError?) -> Bool {
      showInMenuBar || settingsError != nil
    }
  }

  /// The work that waits for a usable settings file, run again when a reset or a repair makes the
  /// file usable: the update check, if enabled, and the login registration, unless the user opted
  /// out.
  @MainActor
  struct SettingsRecoveryFollowUp {
    let updateCheck: LaunchUpdateCheck
    let registerLogin: () throws -> Void

    func run() {
      updateCheck.run()
      do { try registerLogin() } catch {
        FileHandle.standardError.write(
          Data("[Settings] Login registration unavailable: \(error.localizedDescription)\n".utf8)
        )
      }
    }
  }

  /// The button the user pressed in the alert for an unreadable settings file.
  enum SettingsUnreadableChoice: Equatable {
    case showInFinder
    case resetSettings
    case quit

    /// The buttons in the order the alert adds them.
    init(response: NSApplication.ModalResponse) {
      switch response {
      case .alertFirstButtonReturn: self = .showInFinder
      case .alertSecondButtonReturn: self = .resetSettings
      default: self = .quit
      }
    }
  }

  enum SettingsUnreadableAlert {
    /// Show in Finder is the default button; Reset Settings is a normal button marked
    /// destructive, and Quit answers Escape.
    @MainActor
    static func make(reason: String) -> NSAlert {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string("ui.settings.advanced.unreadableTitle")
      alert.informativeText = reason
      alert.addButton(
        withTitle: OJDLocalized.string("platform.macos.ui.settings.advanced.unreadableShowInFinder")
      )
      let reset = alert.addButton(
        withTitle: OJDLocalized.string("ui.settings.advanced.unreadableResetSettings")
      )
      reset.hasDestructiveAction = true
      let quit = alert.addButton(
        withTitle: MainMenuRenderer.title(
          "ui.menu.app.quit",
          appName: OJDLocalized.string("term.app.name")
        )
      )
      quit.keyEquivalent = "\u{1b}"
      return alert
    }
  }

  /// The log line for a feature that does nothing while the settings file can't be read.
  enum SettingsSkipLog {
    static func message(feature: String, file: String, error: any Error) -> String {
      "[Settings] \(file) cannot be read, skipping \(feature): \(error.localizedDescription)\n"
    }

    static func write(feature: String, file: String, error: any Error) {
      FileHandle.standardError.write(
        Data(message(feature: feature, file: file, error: error).utf8)
      )
    }
  }

#endif
