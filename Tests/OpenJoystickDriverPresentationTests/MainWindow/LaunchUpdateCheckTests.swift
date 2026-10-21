import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct LaunchUpdateCheckTests {
  @Test
  @MainActor
  func enabledSettingChecksOnce() {
    var checks = 0
    LaunchUpdateCheck(settingsError: { nil }, isEnabled: { true }, check: { checks += 1 }).run()
    #expect(checks == 1)
  }

  @Test
  @MainActor
  func disabledSettingDoesNotCheck() {
    var checks = 0
    LaunchUpdateCheck(settingsError: { nil }, isEnabled: { false }, check: { checks += 1 }).run()
    #expect(checks == 0)
  }
}
