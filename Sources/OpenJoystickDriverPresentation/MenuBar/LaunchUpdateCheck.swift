import OpenJoystickDriverKit

/// Decides at app launch whether the update check runs: only when the settings file can be read
/// and the user enabled "Check for updates automatically". An unreadable settings file never
/// runs the check on the default.
@MainActor
struct LaunchUpdateCheck {
  enum Outcome: Equatable {
    case checked
    case disabled
    case skippedSettingsUnreadable(SettingsStoreError)
  }

  let settingsError: @MainActor () -> SettingsStoreError?
  let isEnabled: @MainActor () -> Bool
  let check: @MainActor () -> Void

  @discardableResult
  func run() -> Outcome {
    if let error = settingsError() { return .skippedSettingsUnreadable(error) }
    guard isEnabled() else { return .disabled }
    check()
    return .checked
  }
}
