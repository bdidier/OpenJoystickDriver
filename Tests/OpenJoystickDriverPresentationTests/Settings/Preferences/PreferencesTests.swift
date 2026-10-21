import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct PreferencesTests {
  @Test
  @MainActor
  func startAtLoginReflectsTheNativeControllerResult() {
    let launch = LaunchAtLoginStub(isEnabled: false)
    let model = SettingsPreferencesModel(
      settings: SettingsStore(directory: RootedDataDirectory.temporary()),
      launchAtLogin: launch,
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setStartAtLogin(true)

    #expect(model.startAtLogin)
    #expect(launch.setValues == [true])
  }

  @Test
  @MainActor
  func enablingNotificationsRequestsNativeAuthorization() async throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let authorization = NotificationAuthorizationStub(state: .notDetermined)
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization
    )

    model.setControllerNotifications(true)
    await waitUntil("model.controllerNotifications") { model.controllerNotifications }

    #expect(authorization.requestCount == 1)
    #expect(try settings.value(of: .notifyControllerConnected))
    #expect(model.notificationAuthorization == .allowed)
  }

  @Test
  @MainActor
  func staleRefreshDoesNotOverwriteANewerAuthorizationResult() async throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let authorization = HeldSettingsAuthorizationStub()
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization
    )
    for await _ in authorization.settingsStarted { break }

    model.setControllerNotifications(true)
    await waitUntil("model.controllerNotifications") { model.controllerNotifications }
    #expect(model.notificationAuthorization == .allowed)

    authorization.releaseSettings()
    for await _ in authorization.settingsReturned { break }
    for _ in 0..<100 { await Task.yield() }

    #expect(model.notificationAuthorization == .allowed)
    #expect(model.controllerNotifications)
  }

  @Test
  @MainActor
  func disablingNotificationsPersistsImmediately() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.notifyControllerConnected, to: true)
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setControllerNotifications(false)

    #expect(!model.controllerNotifications)
    #expect(try settings.value(of: .notifyControllerConnected) == false)
  }

  @Test
  @MainActor
  func notificationEventsAndSoundPersistIndependently() async throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )

    model.setControllerDisconnectedNotifications(true)
    model.setProfileDeactivatedNotifications(true)
    model.setNotificationSounds(false)
    await waitUntil("the notification settings are applied") {
      model.controllerDisconnectedNotifications && model.profileDeactivatedNotifications
    }

    #expect(try settings.value(of: .notifyControllerDisconnected))
    #expect(try settings.value(of: .notifyProfileDeactivated))
    #expect(try settings.value(of: .notifySounds) == false)
  }

  @Test
  @MainActor
  func testNotificationUsesNativeAuthorizationAndSoundPreference() async throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.notifySounds, to: false)
    let authorization = NotificationAuthorizationStub(state: .notDetermined)
    let delivery = PreferencesNotificationDeliverySpy()
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization,
      notificationDelivery: delivery
    )

    model.sendTestNotification()
    await waitUntil("delivery.deliveryCount == 1") { delivery.deliveryCount == 1 }

    #expect(authorization.requestCount == 1)
    #expect(delivery.deliveryCount == 1)
    #expect(delivery.lastSound == false)
  }

  @Test
  @MainActor
  func refreshPublishesAuthorizationGrantedOutsideTheApp() async {
    let authorization = NotificationAuthorizationStub(state: .denied)
    let model = SettingsPreferencesModel(
      settings: SettingsStore(directory: RootedDataDirectory.temporary()),
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization
    )
    authorization.currentState = .allowed

    model.refreshNotificationAuthorization()
    await waitUntil("model.notificationAuthorization == .allowed") {
      model.notificationAuthorization == .allowed
    }

    #expect(model.notificationAuthorization == .allowed)
  }

  @Test
  @MainActor
  func startAtLoginReportsWhenNativeApprovalIsStillRequired() {
    let launch = LaunchAtLoginStub(isEnabled: false, acceptsChanges: false)
    let model = SettingsPreferencesModel(
      settings: SettingsStore(directory: RootedDataDirectory.temporary()),
      launchAtLogin: launch,
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setStartAtLogin(true)

    #expect(!model.startAtLogin)
    #expect(model.errorMessage != nil)
  }

  @Test
  @MainActor
  func prereleaseChoiceAndUpdateCheckShareTheCLIUpdateEngine() async throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let checker = UpdateCheckerStub(result: .upToDate(current: "1.2.3", latest: "v1.2.3"))
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied),
      updateChecker: checker
    )

    model.setIncludePrereleaseUpdates(true)
    model.checkForUpdates()
    await waitUntil("model.updateState == .upToDate(current: \"1.2.3\", latest: \"v1.2.3\")") {
      model.updateState == .upToDate(current: "1.2.3", latest: "v1.2.3")
    }

    #expect(try settings.value(of: .updatesIncludePrereleases))
    #expect(await checker.includePrereleaseArguments == [true])
  }

  @Test
  @MainActor
  func theMenuBarAndDockChoicesAreNeverBothOff() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    #expect(model.showInMenuBar && !model.showInDock)
    #expect(model.showInMenuBarIsLocked && !model.showInDockIsLocked)
    model.setShowInMenuBar(false)
    #expect(model.showInMenuBar)
    #expect(model.errorMessage != nil)

    model.setShowInDock(true)
    #expect(model.showInDock)
    #expect(try settings.value(of: .showInDock))
    #expect(!model.showInMenuBarIsLocked && !model.showInDockIsLocked)

    model.setShowInMenuBar(false)
    #expect(!model.showInMenuBar)
    #expect(model.showInDockIsLocked && !model.showInMenuBarIsLocked)
    model.setShowInDock(false)
    #expect(model.showInDock)
  }

  @Test
  @MainActor
  func developerToolsChoicePersists() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setDeveloperToolsEnabled(true)

    #expect(model.developerToolsEnabled)
    #expect(try settings.value(of: .developerTools))
  }

  @Test
  @MainActor
  func aChangeFromAnotherStoreReachesTheModel() async throws {
    let directory = RootedDataDirectory.temporary()
    let loginItem = LaunchAtLoginStub(isEnabled: false)
    let model = SettingsPreferencesModel(
      settings: SettingsStore(directory: directory),
      launchAtLogin: loginItem,
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )
    #expect(!model.controllerNotifications)
    #expect(!model.startAtLogin)

    // What `ojd setting` or another process does; the service changes the login item too.
    loginItem.isEnabled = true
    try SettingsStore(directory: directory).update([
      .notifyControllerConnected: true, .launchAtLogin: true,
    ])

    await waitUntil("the model reloads the changed settings") {
      model.controllerNotifications && model.startAtLogin
    }
    #expect(model.controllerNotifications)
    #expect(model.startAtLogin)
  }

  @Test
  @MainActor
  func aGoodReloadClearsTheErrorOfAFailedSettingsRead() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )
    try FileManager.default.createDirectory(
      at: settings.folderURL,
      withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: settings.userFileURL)

    model.reloadSettings()
    #expect(model.errorMessage != nil)

    try FileManager.default.removeItem(at: settings.userFileURL)
    model.reloadSettings()
    #expect(model.errorMessage == nil)
  }
}

final class LaunchAtLoginStub: LaunchAtLoginControlling {
  let isAvailable = true
  var isEnabled: Bool
  private(set) var setValues: [Bool] = []
  private let acceptsChanges: Bool

  init(isEnabled: Bool, acceptsChanges: Bool = true) {
    self.isEnabled = isEnabled
    self.acceptsChanges = acceptsChanges
  }

  func setEnabled(_ enabled: Bool) {
    setValues.append(enabled)
    if acceptsChanges { isEnabled = enabled }
  }
}

final class NotificationAuthorizationStub: NotificationAuthorizationControlling,
  @unchecked Sendable
{
  var currentState: RuntimeNotificationAuthorizationState
  private(set) var requestCount = 0

  init(state: RuntimeNotificationAuthorizationState) { currentState = state }

  func state() -> RuntimeNotificationAuthorizationState { currentState }

  func request() -> (RuntimeNotificationAuthorizationState, String?) {
    requestCount += 1
    currentState = .allowed
    return (.allowed, nil)
  }

  @MainActor
  func openSystemSettings() {}
}

private actor UpdateCheckerStub: ApplicationUpdateChecking {
  let result: UpdateCheckState
  private(set) var includePrereleaseArguments: [Bool] = []

  init(result: UpdateCheckState) { self.result = result }

  func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState {
    await Task.yield()
    includePrereleaseArguments.append(includePrereleases)
    return result
  }
}

private final class PreferencesNotificationDeliverySpy: RuntimeNotificationDelivering {
  private(set) var deliveryCount = 0
  private(set) var lastSound: Bool?

  func deliver(title: String, body: String, sound: Bool) {
    deliveryCount += 1
    lastSound = sound
  }
}

/// Holds the model's initial `settings()` read open until the test releases it, answering it with
/// the state from before authorization was requested.
private final class HeldSettingsAuthorizationStub: NotificationAuthorizationControlling {
  let settingsStarted: AsyncStream<Void>
  let settingsReturned: AsyncStream<Void>
  private let startedContinuation: AsyncStream<Void>.Continuation
  private let returnedContinuation: AsyncStream<Void>.Continuation
  private let release: AsyncStream<Void>
  private let releaseContinuation: AsyncStream<Void>.Continuation

  init() {
    (settingsStarted, startedContinuation) = AsyncStream.makeStream()
    (settingsReturned, returnedContinuation) = AsyncStream.makeStream()
    (release, releaseContinuation) = AsyncStream.makeStream()
  }

  func releaseSettings() { releaseContinuation.yield() }

  func state() -> RuntimeNotificationAuthorizationState { .notDetermined }

  func request() -> (RuntimeNotificationAuthorizationState, String?) { (.allowed, nil) }

  func settings() async -> RuntimeNotificationSettings {
    startedContinuation.yield()
    for await _ in release { break }
    defer { returnedContinuation.yield() }
    return .authorizationOnly(.notDetermined)
  }

  @MainActor
  func openSystemSettings() {}
}
