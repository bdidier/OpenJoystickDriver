#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  enum MainWindowSizingPolicy {
    static let defaultContentSize = NSSize(width: 1_040, height: 700)
    static let minimumContentSize = NSSize(width: 800, height: 560)

    @MainActor
    static func minimumFrameSize(for window: NSWindow) -> NSSize {
      window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
    }
  }

  /// Toolbar layout of the main window: sidebar toggle, the sidebar's tracking separator, then
  /// one selectable group with an item per area.
  enum MainWindowToolbarLayout {
    static let toolbar = NSToolbar.Identifier("OpenJoystickDriver.MainWindowToolbar")
    static let sidebarToggle = NSToolbarItem.Identifier("OpenJoystickDriver.MainWindow.Sidebar")
    static let areas = NSToolbarItem.Identifier("OpenJoystickDriver.MainWindow.Areas")

    static var items: [NSToolbarItem.Identifier] {
      [sidebarToggle, .sidebarTrackingSeparator, .flexibleSpace, areas, .flexibleSpace]
    }

    /// Title key of the sidebar toggle for the sidebar's state.
    static func sidebarToggleTitleKey(sidebarCollapsed: Bool) -> String {
      sidebarCollapsed ? "mainWindow.showSidebar" : "mainWindow.hideSidebar"
    }
  }

  @MainActor
  final class MainWindowController: NSWindowController, NSWindowDelegate, MainWindowPresenting,
    MenuProfileMutating
  {
    let navigation: MainWindowNavigationModel
    private let screens: MainWindowScreens
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let visibilityChanged: @MainActor (Bool) -> Void
    private weak var areaGroup: NSToolbarItemGroup?
    private weak var sidebarToggleItem: NSToolbarItem?
    private var areaObservation: AnyCancellable?
    private var sidebarObservation: NSKeyValueObservation?
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
        console: ConsoleViewModel(),
        libraryArea: LibraryViewModel(),
        access: AccessViewModel(),
        restartApplication: restartApplication,
        openInputTest: openInputTest
      )

      sidebarItem = NSSplitViewItem(
        sidebarWithViewController: NSHostingController(
          rootView: MainWindowSidebar(navigation: navigation)
        )
      )
      sidebarItem.canCollapse = true
      let detailItem = NSSplitViewItem(
        viewController: NSHostingController(
          rootView: MainWindowDetail(
            navigation: navigation,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens
          )
        )
      )
      splitViewController.addSplitViewItem(sidebarItem)
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
      sidebarObservation = sidebarItem.observe(\.isCollapsed, options: [.initial, .new]) {
        [weak self] item, _ in
        let collapsed = item.isCollapsed
        Task { @MainActor in self?.reflectSidebar(collapsed: collapsed) }
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
      toolbar.displayMode = .iconAndLabel
      window.toolbar = toolbar
      if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
    }

    private func reflect(area: MainWindowArea) {
      window?.title = area.title
      if let index = MainWindowArea.allCases.firstIndex(of: area) {
        areaGroup?.selectedIndex = index
      }
    }

    private func reflectSidebar(collapsed: Bool) {
      guard let item = sidebarToggleItem else { return }
      let title = OJDLocalized.string(
        MainWindowToolbarLayout.sidebarToggleTitleKey(sidebarCollapsed: collapsed)
      )
      item.label = title
      item.paletteLabel = title
      item.toolTip = title
      item.image?.accessibilityDescription = title
    }

    @objc
    private func toggleSidebarFromToolbar(_ sender: Any?) {
      splitViewController.toggleSidebar(sender)
    }

    @objc
    private func selectAreaFromToolbar(_ sender: NSToolbarItemGroup) {
      let areas = MainWindowArea.allCases
      guard areas.indices.contains(sender.selectedIndex) else { return }
      if !navigation.requestArea(areas[sender.selectedIndex]) {
        // The switch waits on the discard question or a running mutation; keep the
        // toolbar on the area that is still shown.
        reflect(area: navigation.selectedArea)
      }
    }
  }

  extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.items
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.items
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      []
    }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      switch itemIdentifier {
      case MainWindowToolbarLayout.sidebarToggle:
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(toggleSidebarFromToolbar(_:))
        item.isBordered = true
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        sidebarToggleItem = item
        reflectSidebar(collapsed: sidebarItem.isCollapsed)
        return item
      case MainWindowToolbarLayout.areas:
        let areas = MainWindowArea.allCases
        let images = areas.map { area -> NSImage in
          let image = NSImage(
            systemSymbolName: area.symbolName,
            accessibilityDescription: area.accessibilityLabel
          )
          // Every area symbol exists on macOS 12; a missing one is a build error to fix.
          precondition(image != nil, "Missing SF Symbol \(area.symbolName)")
          return image!
        }
        let group = NSToolbarItemGroup(
          itemIdentifier: itemIdentifier,
          images: images,
          selectionMode: .selectOne,
          labels: areas.map(\.title),
          target: self,
          action: #selector(selectAreaFromToolbar(_:))
        )
        group.controlRepresentation = .expanded
        group.label = OJDLocalized.string("mainWindow.areas")
        group.paletteLabel = group.label
        for (subitem, area) in zip(group.subitems, areas) {
          subitem.toolTip = area.title
        }
        areaGroup = group
        reflect(area: navigation.selectedArea)
        return group
      default: return nil
      }
    }
  }

#endif
