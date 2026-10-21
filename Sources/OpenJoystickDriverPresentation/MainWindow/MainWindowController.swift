#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  enum MainWindowSizingPolicy {
    static let sidebarWidth = (minimum: CGFloat(170), maximum: CGFloat(260))
    static let listWidth = (minimum: CGFloat(200), maximum: CGFloat(320))
    static let minimumDetailWidth: CGFloat = 420
    static let defaultContentSize = NSSize(width: 1_040, height: 700)
    static let minimumContentSize = NSSize(width: 960, height: 560)

    @MainActor
    static func minimumFrameSize(for window: NSWindow) -> NSSize {
      window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
    }
  }

  @MainActor
  final class MainWindowController: NSWindowController, NSWindowDelegate, MainWindowPresenting,
    MenuProfileMutating
  {
    let navigation: MainWindowNavigationModel
    let screens: MainWindowScreens
    private let visibilityChanged: @MainActor (Bool) -> Void
    private let splitViewController = NSSplitViewController()
    private let listItem: NSSplitViewItem
    private var areaObservation: AnyCancellable?
    private var toolbarEnablementObservation: AnyCancellable?
    private var activityModeObservation: AnyCancellable?
    private var summaryObservation: AnyCancellable?
    private var isEnforcingMinimumSize = false

    init(
      runtime: RuntimeViewModel,
      supportReport: SupportReportModel,
      restartApplication: @escaping @MainActor () -> Void,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void,
      visibilityChanged: @escaping @MainActor (Bool) -> Void,
      persistence: any MainWindowAreaPersistence = UserDefaultsMainWindowAreaPersistence()
    ) {
      self.visibilityChanged = visibilityChanged
      navigation = MainWindowNavigationModel(persistence: persistence)
      screens = MainWindowScreens(
        runtime: runtime,
        supportReport: supportReport,
        controllers: ControllersViewModel(runtime: runtime),
        library: ProfileLibraryModel(runtime: runtime),
        profiles: ProfilesViewModel(),
        activity: ActivityModel(
          log: ActivityLogModel(),
          diagnostics: ActivityDiagnosticsModel {
            await ActivityDiagnosticsChecks.run(gateway: supportReport.gateway)
          }
        ),
        errorCodeExplainer: ErrorCodeExplainerModel(),
        libraryArea: LibraryViewModel(),
        access: AccessViewModel(),
        restartApplication: restartApplication,
        openInputTest: openInputTest
      )

      let sidebarItem = NSSplitViewItem(
        sidebarWithViewController: NSHostingController(
          rootView: MainWindowSidebar(navigation: navigation)
        )
      )
      sidebarItem.canCollapse = true
      sidebarItem.minimumThickness = MainWindowSizingPolicy.sidebarWidth.minimum
      sidebarItem.maximumThickness = MainWindowSizingPolicy.sidebarWidth.maximum
      let listItem = NSSplitViewItem(
        contentListWithViewController: NSHostingController(
          rootView: MainWindowListRoot(
            navigation: navigation,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens
          )
        )
      )
      listItem.minimumThickness = MainWindowSizingPolicy.listWidth.minimum
      listItem.maximumThickness = MainWindowSizingPolicy.listWidth.maximum
      listItem.isCollapsed = !navigation.selectedArea.hasListColumn
      self.listItem = listItem
      let detailItem = NSSplitViewItem(
        viewController: NSHostingController(
          rootView: MainWindowRoot(
            navigation: navigation,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens
          )
        )
      )
      detailItem.minimumThickness = MainWindowSizingPolicy.minimumDetailWidth
      splitViewController.addSplitViewItem(sidebarItem)
      splitViewController.addSplitViewItem(listItem)
      splitViewController.addSplitViewItem(detailItem)

      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: MainWindowSizingPolicy.defaultContentSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.contentViewController = splitViewController
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      installSizingPolicy(on: window)

      areaObservation = navigation.$selectedArea.sink { [weak self] area in
        self?.reflect(area: area)
      }
      toolbarEnablementObservation = Publishers.MergeMany(
        runtime.scopedRefreshInFlightPublisher.map { _ in () }.eraseToAnyPublisher(),
        runtime.$remappingState.map { _ in () }.eraseToAnyPublisher(),
        screens.library.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.profiles.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.activity.log.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.activity.diagnostics.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        navigation.objectWillChange.map { _ in () }.eraseToAnyPublisher()
      ).receive(on: DispatchQueue.main).sink { [weak self] in
        self?.window?.toolbar?.validateVisibleItems()
      }
      activityModeObservation = screens.activity.$mode.receive(on: DispatchQueue.main).sink {
        [weak self] _ in
        guard let self else { return }
        showToolbarActions(of: navigation.selectedArea)
      }
      summaryObservation = runtime.$statusState.sink { [weak self] status in
        guard let self else { return }
        window.subtitle = MainWindowSummary.text(for: navigation.selectedArea, status: status)
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: MainWindowPresenting

    func showMainWindow(area: MainWindowArea?) {
      if let area { navigation.requestArea(area) }
      present()
    }

    func showController(id: String) {
      guard navigation.requestArea(.controllers) else {
        present()
        return
      }
      screens.controllers.select(sessionToken: id)
      present()
    }

    func showErrorCodeExplainer() {
      present()
      screens.errorCodeExplainer.isPresented = true
    }

    var selectedControllerID: String? {
      screens.controllers.selectedDevice?.sessionToken.rawValue
    }

    func showInputTest(controllerID: String) {
      guard navigation.requestArea(.controllers) else {
        present()
        return
      }
      showController(id: controllerID)
      guard
        let device = screens.controllers.devices.first(where: {
          $0.sessionToken.rawValue == controllerID
        })
      else { return }
      screens.openInputTest(device)
    }

    // MARK: Profile mutations from menus

    /// Runs a profile mutation of the status or main menu on the shared library under the
    /// Profiles editor's mutation tracking. Returns nil, without running `mutation`, when the
    /// editor holds a mutation.
    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome? {
      let library = screens.library
      return await navigation.trackMenuProfileMutation(request) {
        let result = await mutation(library)
        return MenuProfileMutationOutcome(result: result, lastError: library.lastError)
      }
    }

    func importProfile() {
      present()
      navigation.perform(in: .profiles) { [weak self] in
        self?.screens.profiles.chooseProfileToImport()
      }
    }

    func exportProfile() {
      present()
      navigation.perform(in: .profiles) { [weak self] in
        guard let self, let profile = selectedProfile else { return }
        screens.profiles.exportProfile(profile)
      }
    }

    var hasSelectedProfile: Bool { selectedProfile != nil }

    private var selectedProfile: RemappingProfile? {
      guard case .available(let snapshot) = screens.runtime.remappingState,
        let selectedID = screens.profiles.selectedProfileID
      else { return nil }
      return snapshot.profiles.first { $0.id == selectedID }
    }

    func installRecordOrMod() {
      present()
      navigation.perform(in: .library) { [weak self] in
        guard let url = LibraryFilePicker.chooseRecordOrModFolder() else { return }
        self?.screens.libraryArea.beginInstall(from: url)
      }
    }

    // MARK: Window

    private func present() {
      guard let window else { return }
      window.minSize = MainWindowSizingPolicy.minimumFrameSize(for: window)
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
      visibilityChanged(true)
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      // Hiding keeps the selected area, the screens' state and the window geometry.
      sender.orderOut(nil)
      visibilityChanged(false)
      return false
    }

    func windowWillResize(_ sender: NSWindow, toFrameSize frameSize: NSSize) -> NSSize {
      WindowFramePolicy.fittingSize(
        frameSize,
        minimumSize: MainWindowSizingPolicy.minimumFrameSize(for: sender)
      )
    }

    func windowDidResize(_ notification: Notification) {
      guard !isEnforcingMinimumSize, let window = notification.object as? NSWindow else { return }
      let minimumFrameSize = MainWindowSizingPolicy.minimumFrameSize(for: window)
      let fittedFrame = WindowFramePolicy.fittingFrame(window.frame, minimumSize: minimumFrameSize)
      guard fittedFrame.size != window.frame.size else { return }
      isEnforcingMinimumSize = true
      window.setFrame(fittedFrame, display: true)
      isEnforcingMinimumSize = false
    }

    func windowDidChangeScreen(_ notification: Notification) {
      guard let window else { return }
      WindowFramePolicy.clamp(
        window,
        minimumSize: MainWindowSizingPolicy.minimumFrameSize(for: window)
      )
    }

    private func installSizingPolicy(on window: NSWindow) {
      window.contentMinSize = MainWindowSizingPolicy.minimumContentSize
      window.minSize = MainWindowSizingPolicy.minimumFrameSize(for: window)
      window.setContentSize(MainWindowSizingPolicy.defaultContentSize)
      let autosaveName = "MainWindowGeometry"
      let restoredFrame = window.setFrameUsingName(autosaveName)
      window.setFrameAutosaveName(autosaveName)
      if !restoredFrame { window.center() }
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
    }

    private func configureToolbar(for window: NSWindow) {
      let toolbar = NSToolbar(identifier: MainWindowToolbarLayout.toolbar)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconOnly
      window.toolbar = toolbar
      if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
    }

    private func reflect(area: MainWindowArea) {
      listItem.isCollapsed = !area.hasListColumn
      showToolbarActions(of: area)
      window?.title = area.title
      window?.subtitle = MainWindowSummary.text(for: area, status: screens.runtime.statusState)
    }
  }

  extension MainWindowController {
    /// Replaces the toolbar's area actions with those of `area`.
    func showToolbarActions(of area: MainWindowArea) {
      guard let toolbar = window?.toolbar else { return }
      let fixedCount = MainWindowToolbarLayout.fixedItems.count
      while toolbar.items.count > fixedCount { toolbar.removeItem(at: toolbar.items.count - 1) }
      let actions = area.toolbarActions(activityMode: screens.activity.mode)
      for (offset, action) in actions.enumerated() {
        toolbar.insertItem(withItemIdentifier: action.identifier, at: fixedCount + offset)
      }
    }

    @objc
    func performToolbarAction(_ sender: NSToolbarItem) {
      guard let action = MainWindowToolbarAction(identifier: sender.itemIdentifier),
        isEnabled(action)
      else { return }
      switch action {
      case .refreshControllers: screens.controllers.refresh()
      case .newProfile: screens.profiles.isCreatingProfile = true
      case .importProfile: screens.profiles.chooseProfileToImport()
      case .installLibraryItem: installRecordOrMod()
      case .copyActivityLog: screens.activity.log.copyVisible()
      case .saveActivityLog: saveActivityLog()
      case .showActivityLogInFinder: screens.activity.log.showInFinder()
      case .runDiagnostics: Task { await screens.activity.diagnostics.run() }
      case .activityMode, .activityFilter, .activityLines, .activitySearch:
        preconditionFailure("\(action) has its own control action")
      }
    }

    func isEnabled(_ action: MainWindowToolbarAction) -> Bool {
      switch action {
      case .refreshControllers: return !screens.runtime.isScopedRefreshInFlight
      case .newProfile, .importProfile:
        return !screens.profiles.isActionBlocked(library: screens.library, runtime: screens.runtime)
      case .installLibraryItem, .saveActivityLog, .showActivityLogInFinder: return true
      case .activityMode, .activityFilter, .activityLines, .activitySearch: return true
      case .copyActivityLog: return !screens.activity.log.rows.isEmpty
      case .runDiagnostics: return !screens.activity.diagnostics.isRunning
      }
    }
  }

  extension MainWindowController: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
      MainWindowToolbarAction(identifier: item.itemIdentifier).map(isEnabled) ?? true
    }
  }

  extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.allowedItems
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.items(
        for: navigation.selectedArea,
        activityMode: screens.activity.mode
      )
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      []
    }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      if itemIdentifier == .sidebarTrackingSeparator {
        return NSTrackingSeparatorToolbarItem(
          identifier: itemIdentifier,
          splitView: splitViewController.splitView,
          dividerIndex: 0
        )
      }
      guard let action = MainWindowToolbarAction(identifier: itemIdentifier) else { return nil }
      if let item = makeActivityControlItem(for: action) { return item }
      let item = MainWindowToolbarLayout.makeItem(for: action)
      item.target = self
      item.action = #selector(performToolbarAction(_:))
      return item
    }
  }

#endif
