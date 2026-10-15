import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct SettingsStoreLegacyDefaultsTests {
  private typealias Key = SettingsStore.LegacyDefaultsKey

  private let store = SettingsStore(directory: RootedDataDirectory.temporary())

  private func suite() -> UserDefaults {
    UserDefaults(suiteName: "ojd-legacy-\(UUID().uuidString)")!
  }

  @Test
  func anOptOutAndTheNotificationChoicesMoveIntoTheUserFile() throws {
    let defaults = suite()
    defaults.set(true, forKey: Key.launchAtLoginOptOut)
    defaults.set(true, forKey: Key.controllerConnected)
    defaults.set(false, forKey: Key.sounds)
    defaults.set(true, forKey: Key.includePrereleases)
    defaults.set(true, forKey: Key.developerTools)

    try store.importLegacyDefaults(from: defaults)

    #expect(try store.launchAtLoginOptOut())
    #expect(try store.value(of: .notifyControllerConnected))
    #expect(try store.value(of: .notifySounds) == false)
    #expect(try store.value(of: .updatesIncludePrereleases))
    #expect(try store.value(of: .developerTools))
    for key in Key.all { #expect(defaults.object(forKey: key) == nil, "\(key)") }
  }

  @Test
  func aKindWithoutItsOwnValueKeepsFollowingTheOlderKind() throws {
    let defaults = suite()
    defaults.set(true, forKey: Key.controllerConnected)
    defaults.set(true, forKey: Key.profileActivated)
    defaults.set(false, forKey: Key.profileDeactivated)

    try store.importLegacyDefaults(from: defaults)

    #expect(try store.value(of: .notifyControllerDisconnected))
    #expect(try store.value(of: .notifyProfileActivated))
    #expect(try store.value(of: .notifyProfileDeactivated) == false)
  }

  @Test
  func anExistingUserFileIsNotOverwrittenAndTheKeysStay() throws {
    let defaults = suite()
    try store.set(.developerTools, to: false)
    defaults.set(true, forKey: Key.developerTools)

    try store.importLegacyDefaults(from: defaults)

    #expect(try store.value(of: .developerTools) == false)
    #expect(defaults.object(forKey: Key.developerTools) != nil)
  }

  @Test
  func withNothingToImportNoFileIsCreated() throws {
    try store.importLegacyDefaults(from: suite())

    #expect(!FileManager.default.fileExists(atPath: store.userFileURL.path))
  }
}
