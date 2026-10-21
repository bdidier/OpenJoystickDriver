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
        visibilityChanged: { [weak self] isOpen in
          if isOpen {
            self?.primaryWindowVisibility.opened(.workbench)
          } else {
            self?.primaryWindowVisibility.closed(.workbench)
          }
        }
      )
      settingsWindow = SettingsWindowController(
        gateway: gateway,
        preferences: preferences,
        commandLineTool: commandLineTool
      ) { [weak self] isOpen in
        if isOpen {
          self?.primaryWindowVisibility.opened(.settings)
        } else {
          self?.primaryWindowVisibility.closed(.settings)
        }
      }
    }

    /// Without a status item the main window is the only way into the app, so hiding the item
    /// opens the window.
    private func applyShowInMenuBar(_ shown: Bool) {
      primaryWindowVisibility.keepsDockIcon = !shown
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
        ) { [weak self] isOpen in
          if isOpen {
            self?.primaryWindowVisibility.opened(.inputTest)
          } else {
            self?.primaryWindowVisibility.closed(.inputTest)
          }
        }
      }
      inputTestWindowController?.show(device: device)
    }

    private func installStatusItem() {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      statusItem = item
      if let button = item.button {
        button.toolTip = OJDLocalized.string("app.name")
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        button.image = MenuBarStatusItemImage.make(
          accessibilityDescription: OJDLocalized.string("a11y.menuBar.statusItem")
        )
        button.setAccessibilityLabel(OJDLocalized.string("a11y.menuBar.statusItem"))
      }
      updateStatusMenu()
      // Use the action path rather than assigning a menu directly so each opening refreshes its
      // snapshot before the menu is shown.
      item.menu = nil
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

    @objc
    private func showStatusMenu(_ sender: Any?) {
      refreshLiveStatus()
      updateStatusMenu()
      guard let menu = statusMenu, let button = statusItem?.button else { return }
      // Pop up the same native menu on every click after the asynchronous status refresh starts.
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
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

    private func updateStatusMenu() {
      statusMenu = makeStatusMenu(
        from: StatusItemModel.entries(for: menuBarViewModel.statusItemState),
        title: OJDLocalized.string("app.name")
      )
    }
  }

#endif
