#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  /// The SwiftUI content of one pane.
  private struct SettingsPaneContent: View {
    let pane: SettingsWindowPane
    let preferences: SettingsPreferencesModel
    let commandLineTool: CommandLineToolModel
    let developerTools: DeveloperToolsViewModel
    let runtime: RuntimeViewModel

    var body: some View {
      switch pane {
      case .general: GeneralPaneView(preferences: preferences)
      case .notifications: NotificationsPaneView(preferences: preferences)
      case .advanced:
        AdvancedPaneView(
          preferences: preferences,
          commandLineTool: commandLineTool,
          developerTools: developerTools,
          runtime: runtime
        )
      }
    }
  }

  /// The pane the Settings window shows: the content of the selected pane.
  private struct SettingsWindowContent: View {
    @ObservedObject
    var panes: SettingsWindowPaneModel
    let content: (SettingsWindowPane) -> SettingsPaneContent

    var body: some View { content(panes.selected) }
  }

  /// The Settings window: toolbar buttons choose the pane, and the window title is the pane title.
  @MainActor
  final class SettingsWindowController: NSWindowController, NSWindowDelegate,
    SettingsWindowPresenting
  {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.SettingsToolbar"
    )
    private let panes: SettingsWindowPaneModel
    let developerTools: DeveloperToolsViewModel
    private let preferences: SettingsPreferencesModel
    private let commandLineTool: CommandLineToolModel
    /// Whether the app left the foreground after the window last read the pane state, so that
    /// coming back reads it once; showing the window reads it and clears this, so the activation
    /// that follows a show reads nothing more.
    private var refreshOnActivation = false
    private var isShown = false
    private var developerToolsAreRunning = false
    private weak var toolbar: NSToolbar?
    private let visibilityChanged: @MainActor (Bool) -> Void
    private let makeContent: (SettingsWindowPane) -> SettingsPaneContent
    private var contentChanges: [AnyCancellable] = []
    private var fitting: RunLoopCoalescer?

    /// - Parameters:
    ///   - gateway: the service connection the developer tools in Advanced read.
    ///   - runtime: the driver extension state and actions of Advanced.
    ///   - preferences: the switches of General, Notifications and Advanced.
    ///   - commandLineTool: the command-line tool link of Advanced.
    ///   - visibilityChanged: called with true when the window is shown and false when it closes.
    init(
      gateway: any ApplicationServiceGateway,
      runtime: RuntimeViewModel,
      preferences: SettingsPreferencesModel,
      commandLineTool: CommandLineToolModel,
      visibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
      self.visibilityChanged = visibilityChanged
      self.preferences = preferences
      self.commandLineTool = commandLineTool
      panes = SettingsWindowPaneModel()
      developerTools = DeveloperToolsViewModel(gateway: gateway)
      let developerTools = developerTools
      let makeContent = { (pane: SettingsWindowPane) in
        SettingsPaneContent(
          pane: pane,
          preferences: preferences,
          commandLineTool: commandLineTool,
          developerTools: developerTools,
          runtime: runtime
        )
      }
      self.makeContent = makeContent
      let window = SettingsWindow(
        contentRect: NSRect(
          x: 0,
          y: 0,
          width: SettingsWindowPane.contentWidth,
          height: SettingsWindowPane.minimumContentHeight
        ),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.hidesOnDeactivate = false
      let hostingView = NSHostingView(
        rootView: SettingsWindowContent(panes: panes, content: makeContent)
      )
      // The window height follows the pane through `paneChanged`, capped to the screen. The
      // hosting view sits in a container that positions it by autoresizing and has no
      // constraints, so on every macOS version the content's ideal height cannot become the
      // window's minimum size (on macOS 12, which has no `sizingOptions`, this container is the
      // only guard); macOS 13 and later also stop the hosting view from sizing itself.
      if #available(macOS 13, *) { hostingView.sizingOptions = [] }
      let container = NSView(
        frame: NSRect(x: 0, y: 0, width: SettingsWindowPane.contentWidth, height: 0)
      )
      hostingView.translatesAutoresizingMaskIntoConstraints = true
      hostingView.frame = container.bounds
      hostingView.autoresizingMask = [.width, .height]
      container.addSubview(hostingView)
      window.contentView = container
      super.init(window: window)
      window.delegate = self
      configureToolbar(on: window)
      paneChanged(animated: false)
      window.center()
      fitting = RunLoopCoalescer { [weak self] in
        self?.syncDeveloperTools()
        guard self?.window?.isVisible == true else { return }
        self?.paneChanged(animated: true)
      }
      // Each publisher announces a change before it is applied; the coalescer measures on a later
      // turn, once the content shows it. Fitting changes only the window, never these models.
      contentChanges = [
        preferences.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        developerTools.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        commandLineTool.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        runtime.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
          .sink { [weak self] _ in self?.refreshOnActivation = true },
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
          .sink { [weak self] _ in
            guard self?.refreshOnActivation == true else { return }
            self?.refreshOnActivation = false
            self?.refreshPaneState()
          },
        NotificationCenter.default.publisher(
          for: NSApplication.didChangeScreenParametersNotification
        ).sink { [weak self] _ in self?.paneChanged(animated: false) },
      ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSettings(pane: SettingsWindowPane?) {
      if let pane {
        panes.select(pane)
        paneChanged(animated: window?.isVisible == true)
      }
      isShown = true
      syncDeveloperTools()
      refreshPaneState()
      refreshOnActivation = false
      visibilityChanged(true)
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Fits the window to the screen it moved to, whose visible area may be smaller.
    func windowDidChangeScreen(_ notification: Notification) { paneChanged(animated: false) }

    func windowWillClose(_ notification: Notification) {
      isShown = false
      syncDeveloperTools()
      visibilityChanged(false)
    }

    /// Reads the state the selected pane shows from the system: the notification permission for
    /// Notifications, the command-line tool link for Advanced. The window drives these reads, so
    /// the offscreen view that measures a pane never starts them.
    func refreshPaneState() {
      guard isShown else { return }
      switch panes.selected {
      case .general: break
      case .notifications: preferences.refreshNotificationAuthorization()
      case .advanced: commandLineTool.refresh()
      }
    }

    /// Reads the controller diagnostics while the window shows Advanced with developer tools on,
    /// and stops them otherwise. This is the only place that starts or stops the reads.
    func syncDeveloperTools() {
      let wanted = isShown && panes.selected == .advanced && preferences.developerToolsEnabled
      guard wanted != developerToolsAreRunning else { return }
      developerToolsAreRunning = wanted
      if wanted { developerTools.requestRefresh() } else { developerTools.close() }
    }

    private func configureToolbar(on window: NSWindow) {
      let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconAndLabel
      window.toolbar = toolbar
      window.toolbarStyle = .preference
      self.toolbar = toolbar
    }

    /// Sets the title of the selected pane and resizes the window's height to the pane's height,
    /// keeping its top edge in place unless the window would then leave the screen's visible area.
    private func paneChanged(animated: Bool) {
      guard let window else { return }
      window.title = OJDLocalized.string(panes.titleKey)
      toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(
        panes.selected.toolbarItemIdentifier
      )
      let fitting = fittingHeight(of: panes.selected)
      let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
      let visibleHeight =
        (window.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
      let size = SettingsWindowPane.contentSize(
        fittingHeight: fitting,
        availableHeight: SettingsWindowPane.availableContentHeight(
          visibleHeight: visibleHeight,
          chromeHeight: chrome
        )
      )
      guard
        window.contentRect(forFrameRect: window.frame).size
          != NSSize(
            width: size.width,
            height: size.height
          )
      else { return }
      var frame = window.frameRect(
        forContentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height)
      )
      frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
      if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
      }
      window.setFrame(frame, display: true, animate: animated)
    }

    /// The height the pane's content takes at the window's width.
    private func fittingHeight(of pane: SettingsWindowPane) -> Double {
      let probe = NSHostingView(
        rootView: makeContent(pane).frame(width: SettingsWindowPane.contentWidth)
          .fixedSize(horizontal: false, vertical: true)
      )
      return Double(probe.fittingSize.height)
    }

    @objc
    private func paneButtonClicked(_ sender: NSToolbarItem) {
      guard let pane = SettingsWindowPane(toolbarItemIdentifier: sender.itemIdentifier.rawValue)
      else { return }
      panes.select(pane)
      syncDeveloperTools()
      refreshPaneState()
      paneChanged(animated: true)
    }
  }

  extension SettingsWindowController: NSToolbarDelegate {
    private var paneIdentifiers: [NSToolbarItem.Identifier] {
      panes.panes.map { NSToolbarItem.Identifier($0.toolbarItemIdentifier) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      paneIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      paneIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      paneIdentifiers
    }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      guard let pane = SettingsWindowPane(toolbarItemIdentifier: itemIdentifier.rawValue)
      else { return nil }
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      let title = OJDLocalized.string(pane.titleKey)
      let description = OJDLocalized.string(pane.accessibilityKey)
      item.label = title
      item.paletteLabel = title
      item.toolTip = description
      item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: description)
      item.target = self
      item.action = #selector(paneButtonClicked(_:))
      return item
    }
  }

#endif
