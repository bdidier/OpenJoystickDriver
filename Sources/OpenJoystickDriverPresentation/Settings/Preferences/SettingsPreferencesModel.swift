#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  protocol ApplicationUpdateChecking: Sendable {
    func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState
  }

  extension UpdateChecker: ApplicationUpdateChecking {}

  @MainActor
  final class SettingsPreferencesModel: ObservableObject {
    @Published
    private(set) var startAtLogin: Bool
    @Published
    private(set) var controllerNotifications: Bool
    @Published
    private(set) var controllerDisconnectedNotifications: Bool
    @Published
    private(set) var profileNotifications: Bool
    @Published
    private(set) var profileDeactivatedNotifications: Bool
    @Published
    private(set) var notificationSounds: Bool
    @Published
    private(set) var notificationAuthorization: RuntimeNotificationAuthorizationState
    @Published
    private(set) var notificationSystemSettings: RuntimeNotificationSettings
    @Published
    private(set) var showInMenuBar: Bool
    @Published
    private(set) var showInDock: Bool
    @Published
    private(set) var checkUpdatesAutomatically: Bool
    @Published
    private(set) var includePrereleaseUpdates: Bool
    @Published
    private(set) var developerToolsEnabled: Bool
    @Published
    private(set) var updateState: UpdateCheckState = .idle
    @Published
    private(set) var errorMessage: String?
    /// Why the settings file cannot be used, or `nil` while it can. While it is set, the switches
    /// show the built-in defaults and features that read settings do nothing.
    @Published
    private(set) var settingsFileError: SettingsStoreError?

    let launchAtLoginIsAvailable: Bool

    private let settings: SettingsStore
    private var watcher: SettingsWatcher?
    private let launchAtLogin: any LaunchAtLoginControlling
    private let notificationAuthorizationController: any NotificationAuthorizationControlling
    /// Counts authorization reads. The controller answers off the main actor, so a refresh that
    /// started before a newer read can finish after it; its result is then stale and dropped.
    private var notificationAuthorizationReads = 0
    private let updateChecker: any ApplicationUpdateChecking
    private let notificationDelivery: any RuntimeNotificationDelivering

    init(
      settings: SettingsStore = SettingsStore(),
      launchAtLogin: (any LaunchAtLoginControlling)? = nil,
      notificationAuthorization: any NotificationAuthorizationControlling =
        SystemNotificationAuthorizationController(),
      updateChecker: any ApplicationUpdateChecking = UpdateChecker(),
      notificationDelivery: any RuntimeNotificationDelivering = SystemRuntimeNotificationDelivery()
    ) {
      let launchAtLogin = launchAtLogin ?? SystemLaunchAtLoginController(settings: settings)
      self.settings = settings
      self.launchAtLogin = launchAtLogin
      self.notificationAuthorizationController = notificationAuthorization
      self.updateChecker = updateChecker
      self.notificationDelivery = notificationDelivery
      self.launchAtLoginIsAvailable = launchAtLogin.isAvailable
      self.startAtLogin = launchAtLogin.isEnabled
      self.notificationAuthorization = .checking
      self.notificationSystemSettings = .authorizationOnly(.checking)
      self.controllerNotifications = ApplicationSettingKey.notifyControllerConnected.defaultValue
      self.controllerDisconnectedNotifications =
        ApplicationSettingKey.notifyControllerDisconnected.defaultValue
      self.profileNotifications = ApplicationSettingKey.notifyProfileActivated.defaultValue
      self.profileDeactivatedNotifications =
        ApplicationSettingKey.notifyProfileDeactivated.defaultValue
      self.notificationSounds = ApplicationSettingKey.notifySounds.defaultValue
      self.showInMenuBar = ApplicationSettingKey.showInMenuBar.defaultValue
      self.showInDock = ApplicationSettingKey.showInDock.defaultValue
      self.checkUpdatesAutomatically = ApplicationSettingKey.updatesCheckAutomatically.defaultValue
      self.includePrereleaseUpdates = ApplicationSettingKey.updatesIncludePrereleases.defaultValue
      self.developerToolsEnabled = ApplicationSettingKey.developerTools.defaultValue
      reloadSettings()
      // A change from `ojd setting` or another process shows while the window is open.
      watcher = SettingsWatcher(store: settings) { [weak self] in
        Task { @MainActor in self?.reloadSettings() }
      }
      refreshNotificationAuthorization()
    }

    /// Reads the user settings file and the login item again; a file that cannot be used shows in
    /// `errorMessage` and `settingsFileError` and leaves the switches as they are.
    func reloadSettings() {
      startAtLogin = launchAtLogin.isEnabled
      let stored: SettingsDocument
      do { stored = try settings.load() } catch {
        report(error)
        return
      }
      if settingsFileError != nil {
        settingsFileError = nil
        errorMessage = nil
      }
      func value(_ key: ApplicationSettingKey) -> Bool { stored[key] ?? key.defaultValue }
      controllerNotifications = value(.notifyControllerConnected)
      controllerDisconnectedNotifications = value(.notifyControllerDisconnected)
      profileNotifications = value(.notifyProfileActivated)
      profileDeactivatedNotifications = value(.notifyProfileDeactivated)
      notificationSounds = value(.notifySounds)
      showInMenuBar = value(.showInMenuBar)
      showInDock = value(.showInDock)
      checkUpdatesAutomatically = value(.updatesCheckAutomatically)
      includePrereleaseUpdates = value(.updatesIncludePrereleases)
      developerToolsEnabled = value(.developerTools)
    }

    func setStartAtLogin(_ enabled: Bool) {
      do {
        try launchAtLogin.setEnabled(enabled)
        startAtLogin = launchAtLogin.isEnabled
        if enabled && !startAtLogin {
          errorMessage = OJDLocalized.string(
            "settings.startAtLoginApprovalRequired"
          )
        } else {
          errorMessage = nil
        }
      } catch {
        startAtLogin = launchAtLogin.isEnabled
        report(error)
      }
    }

    func setControllerNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .controllers)
    }

    func setProfileNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .profiles)
    }

    func setControllerDisconnectedNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .controllerDisconnections)
    }

    func setProfileDeactivatedNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .profileDeactivations)
    }

    func setNotificationSounds(_ enabled: Bool) {
      guard persist(.notifySounds, enabled) else { return }
      notificationSounds = enabled
    }

    func sendTestNotification() { setNotificationPreference(true, preference: .test) }

    func setShowInMenuBar(_ enabled: Bool) {
      guard persist(.showInMenuBar, enabled) else { return }
      showInMenuBar = enabled
    }

    func setShowInDock(_ enabled: Bool) {
      guard persist(.showInDock, enabled) else { return }
      showInDock = enabled
    }

    /// Show in menu bar and Show in Dock cannot both be off, so the one that is on stays on.
    var showInMenuBarIsLocked: Bool { showInMenuBar && !showInDock }

    var showInDockIsLocked: Bool { showInDock && !showInMenuBar }

    func setCheckUpdatesAutomatically(_ enabled: Bool) {
      guard persist(.updatesCheckAutomatically, enabled) else { return }
      checkUpdatesAutomatically = enabled
    }

    func setIncludePrereleaseUpdates(_ enabled: Bool) {
      guard persist(.updatesIncludePrereleases, enabled) else { return }
      includePrereleaseUpdates = enabled
    }

    func setDeveloperToolsEnabled(_ enabled: Bool) {
      guard persist(.developerTools, enabled) else { return }
      developerToolsEnabled = enabled
    }

    /// Checks for a newer version and shows the result in `updateState`. With
    /// `announcingAvailableUpdate`, a newer version also posts a notification; an up-to-date
    /// result or a failure posts none and stays in `updateState`.
    func checkForUpdates(announcingAvailableUpdate: Bool = false) {
      guard updateState != .checking else { return }
      updateState = .checking
      let includePrereleases = includePrereleaseUpdates
      Task { @MainActor [weak self, updateChecker] in
        let state = await updateChecker.check(
          currentVersion: ApplicationVersion.current,
          includePrereleases: includePrereleases
        )
        guard let self else { return }
        self.updateState = state
        if announcingAvailableUpdate, case .available(let info) = state {
          self.notificationDelivery.deliver(
            title: OJDLocalized.string("settings.updateAvailable"),
            body: OJDLocalized.formatted("settings.updateAvailableBody", info.tagName),
            sound: self.notificationSounds
          )
        }
      }
    }

    func openAvailableUpdate() {
      guard case .available(let info) = updateState else { return }
      NSWorkspace.shared.open(info.htmlURL)
    }

    func openNotificationSettings() { notificationAuthorizationController.openSystemSettings() }

    func dismissError() { errorMessage = nil }

    func refreshNotificationAuthorization() {
      notificationAuthorizationReads += 1
      let read = notificationAuthorizationReads
      Task { [weak self, notificationAuthorizationController] in
        let settings = await notificationAuthorizationController.settings()
        guard let self, read == self.notificationAuthorizationReads else { return }
        let state = settings.authorization
        self.notificationAuthorization = state
        self.notificationSystemSettings = settings
        if state == .denied {
          let notifications: [ApplicationSettingKey] = [
            .notifyControllerConnected, .notifyControllerDisconnected, .notifyProfileActivated,
            .notifyProfileDeactivated,
          ]
          guard self.persist(Dictionary(uniqueKeysWithValues: notifications.map { ($0, false) }))
          else { return }
          self.controllerNotifications = false
          self.controllerDisconnectedNotifications = false
          self.profileNotifications = false
          self.profileDeactivatedNotifications = false
        }
      }
    }

    /// Stores `values` in the user settings file; a failure shows in `errorMessage`.
    private func persist(_ key: ApplicationSettingKey, _ value: Bool) -> Bool {
      persist([key: value])
    }

    private func persist(_ values: [ApplicationSettingKey: Bool]) -> Bool {
      do {
        try settings.update(values)
        return true
      } catch {
        report(error)
        return false
      }
    }

    /// Shows `error`; a settings file error that makes the file unusable is also kept typed.
    private func report(_ error: any Error) {
      errorMessage = error.localizedDescription
      if let error = error as? SettingsStoreError, error.fileIsUnusable {
        settingsFileError = error
      }
    }

    /// Moves the settings file to the Trash and reads the defaults; a failure shows in
    /// `errorMessage`.
    func resetSettings() {
      do { try settings.moveToTrash() } catch {
        errorMessage = error.localizedDescription
        return
      }
      reloadSettings()
    }

    /// Shows the settings file in Finder, or its folder while there is no file.
    func showSettingsFileInFinder() {
      let file = settings.userFileURL
      if FileManager.default.fileExists(atPath: file.path) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
      } else {
        NSWorkspace.shared.open(settings.folderURL)
      }
    }

    private func setNotificationPreference(_ enabled: Bool, preference: NotificationPreference) {
      guard enabled else {
        guard persist(preference, false) else { return }
        update(preference, enabled: false)
        errorMessage = nil
        return
      }
      notificationAuthorizationReads += 1
      Task { [weak self, notificationAuthorizationController] in
        let state = await notificationAuthorizationController.state()
        guard let self else { return }
        self.notificationAuthorization = state
        switch state {
        case .allowed:
          self.acceptNotificationPreference(preference)
          self.refreshNotificationAuthorization()
        case .notDetermined, .checking: self.requestNotificationAuthorization(preference)
        case .denied: self.rejectNotificationPreference(preference, errorDescription: nil)
        }
      }
    }

    private func requestNotificationAuthorization(_ preference: NotificationPreference) {
      notificationAuthorizationReads += 1
      Task { [weak self, notificationAuthorizationController] in
        let (state, errorDescription) = await notificationAuthorizationController.request()
        guard let self else { return }
        self.notificationAuthorization = state
        if state == .allowed && errorDescription == nil {
          self.acceptNotificationPreference(preference)
        } else {
          self.rejectNotificationPreference(preference, errorDescription: errorDescription)
        }
      }
    }

    private func acceptNotificationPreference(_ preference: NotificationPreference) {
      if preference == .test {
        notificationDelivery.deliver(
          title: OJDLocalized.string(
            "notifications.testTitle"
          ),
          body: OJDLocalized.string(
            "notifications.testBody"
          ),
          sound: notificationSounds
        )
      } else {
        guard persist(preference, true) else { return }
        update(preference, enabled: true)
      }
      errorMessage = nil
    }

    private func rejectNotificationPreference(
      _ preference: NotificationPreference,
      errorDescription: String?
    ) {
      if preference != .test, persist(preference, false) {
        update(preference, enabled: false)
      }
      errorMessage =
        errorDescription
        ?? OJDLocalized.string(
          "settings.notificationsDenied"
        )
    }

    private func update(_ preference: NotificationPreference, enabled: Bool) {
      switch preference {
      case .controllers: controllerNotifications = enabled
      case .controllerDisconnections: controllerDisconnectedNotifications = enabled
      case .profiles: profileNotifications = enabled
      case .profileDeactivations: profileDeactivatedNotifications = enabled
      case .test: break
      }
    }

    private func persist(_ preference: NotificationPreference, _ value: Bool) -> Bool {
      guard let key = preference.settingKey else { return true }
      return persist(key, value)
    }
  }

  private enum NotificationPreference: Sendable, Equatable {
    case controllers
    case controllerDisconnections
    case profiles
    case profileDeactivations
    case test

    /// The setting that stores the preference; the test notification has none.
    var settingKey: ApplicationSettingKey? {
      switch self {
      case .controllers: return .notifyControllerConnected
      case .controllerDisconnections: return .notifyControllerDisconnected
      case .profiles: return .notifyProfileActivated
      case .profileDeactivations: return .notifyProfileDeactivated
      case .test: return nil
      }
    }
  }

#endif
