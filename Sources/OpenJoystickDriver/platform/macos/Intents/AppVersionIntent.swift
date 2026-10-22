#if canImport(AppIntents)
  import AppIntents
  import Foundation

  /// The Shortcuts action that returns the version of the installed app.
  @available(macOS 13, *)
  struct AppVersionIntent: AppIntent {
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.appVersion.title"
    )
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.appVersion.description"
      )
    )

    func perform() -> some IntentResult & ReturnsValue<String> {
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      return .result(value: version as? String ?? "")
    }
  }
#endif
