#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  extension MenuBarCoordinator {

    package func run() -> Never {
      Self.activeCoordinator = self
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.delegate = self
      makeWindows()
      application.mainMenu = makeApplicationMenu()
      application.run()

      // Normal termination has already awaited stopRuntime() in applicationShouldTerminate.
      // Exit only after AppKit has completed that reply; the signal path retains its own exit path.
      exit(0)
    }

    package func applicationDidFinishLaunching(_ notification: Notification) {
      bundledNotificationCenter?.delegate = notificationPresenter
      refreshStatus()
      controllerInventoryObserver = NotificationCenter.default.addObserver(
        forName: .ojdControllerInventoryDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in Task { @MainActor [weak self] in self?.refreshLiveStatus() } }
      Task { @MainActor in await viewModel.startSystemExtensionSetup() }
      LaunchUpdateCheck(
        isEnabled: { [preferences] in preferences.checkUpdatesAutomatically },
        check: { [preferences] in preferences.checkForUpdates(announcingAvailableUpdate: true) }
      ).run()
      showInDockObservation = preferences.$showInDock.removeDuplicates().sink {
        [weak self] shown in self?.dockIcon.showsAlways = shown
      }
      showInMenuBarObservation = preferences.$showInMenuBar.removeDuplicates().sink {
        [weak self] shown in self?.applyShowInMenuBar(shown)
      }
      // The service sends no controller attach or detach notification to the app, so this poll is
      // the only source of live controller changes.
      liveStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.refreshLiveStatus() }
      }
    }

    package func applicationDidBecomeActive(_ notification: Notification) {
      Task { @MainActor in await viewModel.refreshSystemExtensionSetup() }
    }

    package func applicationShouldHandleReopen(
      _ sender: NSApplication,
      hasVisibleWindows flag: Bool
    ) -> Bool {
      refreshLiveStatus()
      mainWindow?.showMainWindow(area: nil)
      return true
    }

    package func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    {
      termination.request {
        self.stopLiveStatus()
        self.removeStatusItem()
        self.inputTestWindowController?.stop()
        await self.stopRuntime()
      } relaunch: {
        await self.relaunchApplication()
      } reply: {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }

    func terminateFromShutdownSignal() { NSApplication.shared.terminate(nil) }

    @discardableResult
    package static func terminateFromShutdownSignalIfRunning() -> Bool {
      guard let activeCoordinator else { return false }
      activeCoordinator.terminateFromShutdownSignal()
      return true
    }

    package func applicationWillTerminate(_ notification: Notification) {
      stopLiveStatus()
      removeStatusItem()
    }

    @objc
    func quit(_ sender: Any?) { NSApplication.shared.terminate(sender) }

    private func restartApplication() {
      termination.requestRelaunch { NSApplication.shared.terminate(nil) }
    }

    private func relaunchApplication() async {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      await withCheckedContinuation { continuation in
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        { _, error in
          if let error { fputs("Failed to relaunch OpenJoystickDriver: \(error)\n", stderr) }
          continuation.resume()
        }
      }
    }

    /// Creates the main and Settings windows once; they hide on close and keep their state.
    func makeWindows() {
      mainWindow = MainWindowController(
        runtime: viewModel,
        supportReport: supportReport,
        restartApplication: { [weak self] in self?.restartApplication() },
        openInputTest: { [weak self] device in self?.openInputTest(for: device) },
        visibilityChanged: { [weak self] isOpen in self?.dockIcon.setOpen(.workbench, isOpen) }
      )
      settingsWindow = SettingsWindowController(
        gateway: gateway,
        runtime: viewModel,
        preferences: preferences,
        commandLineTool: commandLineTool
      ) { [weak self] isOpen in self?.dockIcon.setOpen(.settings, isOpen) }
    }

    /// Hiding the status item opens the main window, so the change shows where the app is now.
    private func applyShowInMenuBar(_ shown: Bool) {
      if shown {
        guard statusItem == nil else { return }
        installStatusItem()
      } else {
        removeStatusItem()
        mainWindow?.showMainWindow(area: nil)
      }
    }

    private func openInputTest(for device: ApplicationServiceDeviceDescription) {
      if inputTestWindowController == nil {
        inputTestWindowController = InputTestWindowController(
          gateway: gateway,
          runtimeViewModel: viewModel
        ) { [weak self] isOpen in self?.dockIcon.setOpen(.inputTest, isOpen) }
      }
      inputTestWindowController?.show(device: device)
    }

    private func installStatusItem() {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      statusItem = item
      if let button = item.button {
        button.toolTip = OJDLocalized.string("app.name")
        button.image = MenuBarStatusItemImage.make(
          accessibilityDescription: OJDLocalized.string("a11y.menuBar.statusItem")
        )
        button.setAccessibilityLabel(OJDLocalized.string("a11y.menuBar.statusItem"))
      }
      statusMenuTracker.onWillOpen = { [weak self] in self?.refreshLiveStatus() }
      // The menu runs the chosen item's action after it closes; rebuilding first would
      // release that item.
      statusMenuTracker.onDidClose = { [weak self] in
        DispatchQueue.main.async { self?.updateStatusMenu() }
      }
      updateStatusMenu()
    }

    private func stopLiveStatus() {
      liveStatusTimer?.invalidate()
      liveStatusTimer = nil
      if let controllerInventoryObserver {
        NotificationCenter.default.removeObserver(controllerInventoryObserver)
        self.controllerInventoryObserver = nil
      }
    }

    private func removeStatusItem() {
      guard let item = statusItem else { return }
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
      statusMenu = nil
    }

    private func refreshStatus() {
      updateStatusMenu()
      Task { @MainActor [weak self] in
        guard let self else { return }
        await menuBarViewModel.refresh()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        updateStatusMenu()
      }
    }

    private func refreshLiveStatus() {
      Task { @MainActor [weak self] in
        guard let self else { return }
        let statusChanged = await menuBarViewModel.refreshLiveStatus()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        if statusChanged { updateStatusMenu() }
      }
    }

    /// Installs the current menu as the status item's menu, which AppKit places under the button.
    /// An open menu is left alone and replaced when it closes.
    private func updateStatusMenu() {
      guard !statusMenuTracker.isOpen else { return }
      let menu = makeStatusMenu(
        from: StatusItemModel.entries(for: menuBarViewModel.statusItemState),
        title: OJDLocalized.string("app.name")
      )
      menu.delegate = statusMenuTracker
      statusMenu = menu
      statusItem?.menu = menu
    }
  }

#endif
