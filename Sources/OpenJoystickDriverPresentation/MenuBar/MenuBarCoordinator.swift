#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  enum MenuBarStatusItemImage {
    static func make(accessibilityDescription: String) -> NSImage? {
      let image = NSImage(
        systemSymbolName: "gamecontroller",
        accessibilityDescription: accessibilityDescription
      )
      image?.isTemplate = true
      return image
    }
  }

  @MainActor
  package final class MenuBarCoordinator: NSObject, NSApplicationDelegate {
    let stopRuntime: @MainActor () async -> Void
    let viewModel: RuntimeViewModel
    let menuBarViewModel: MenuBarViewModel
    let supportReport: SupportReportModel
    let gateway: any ApplicationServiceGateway & InputTestDeviceGateway
    let gatewayChangeSource: any ControllerChangeSource

    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    let statusMenuTracker = StatusMenuTracker()
    /// The main window; the status item and main menu open areas only through it.
    var mainWindow: (any MenuProfileMutating)?
    /// The Settings window.
    var settingsWindow: (any SettingsWindowPresenting)?
    /// App preferences, shared with the Settings window; `showInMenuBar` adds or removes the
    /// status item and `showInDock` the Dock icon.
    let preferences: SettingsPreferencesModel
    /// The command-line tool link, shown by the Settings window.
    let commandLineTool = CommandLineToolModel()
    var showInMenuBarObservation: AnyCancellable?
    var showInDockObservation: AnyCancellable?
    var inputTestWindowController: InputTestWindowController?
    var controllerLiveUpdates: ControllerLiveUpdates?
    let notificationMonitor = RuntimeNotificationMonitor()
    let notificationPresenter = RuntimeNotificationCenterDelegate()
    let termination = MenuBarTermination()
    let dockIcon = DockIconController()
    static weak var activeCoordinator: MenuBarCoordinator?

    package init(
      stopRuntime: @escaping @MainActor () async -> Void,
      gateway: ApplicationServiceClientGateway,
      systemExtensionSetup: any SystemExtensionSetupClient,
      listenerState: ServiceListenerState
    ) {
      self.stopRuntime = stopRuntime
      self.gateway = gateway
      self.gatewayChangeSource = gateway
      self.preferences = SettingsPreferencesModel(testNotifications: gateway)
      self.viewModel = RuntimeViewModel(
        gateway: gateway,
        systemExtensionSetup: SystemExtensionSetupCoordinator(client: systemExtensionSetup),
        listenerState: listenerState
      )
      self.menuBarViewModel = MenuBarViewModel(runtime: self.viewModel)
      self.supportReport = SupportReportModel(gateway: gateway)
      super.init()
    }
  }

#else

  final class MenuBarCoordinator {}

#endif
