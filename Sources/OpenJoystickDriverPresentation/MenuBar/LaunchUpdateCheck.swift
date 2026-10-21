/// Decides at app launch whether the update check runs: only when the user enabled
/// "Check for updates automatically".
@MainActor
struct LaunchUpdateCheck {
  let isEnabled: @MainActor () -> Bool
  let check: @MainActor () -> Void

  func run() {
    guard isEnabled() else { return }
    check()
  }
}
