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
    private let developerTools: DeveloperToolsViewModel
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
      window.contentView = NSHostingView(
        rootView: SettingsWindowContent(panes: panes, content: makeContent)
      )
      super.init(window: window)
      window.delegate = self
      configureToolbar(on: window)
      paneChanged(animated: false)
      window.center()
      fitting = RunLoopCoalescer { [weak self] in
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
      ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSettings(pane: SettingsWindowPane?) {
      if let pane {
        panes.select(pane)
        paneChanged(animated: window?.isVisible == true)
      }
      visibilityChanged(true)
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { visibilityChanged(false) }

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
    /// keeping its top edge in place.
    private func paneChanged(animated: Bool) {
      guard let window else { return }
      window.title = OJDLocalized.string(panes.titleKey)
      toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(
        panes.selected.toolbarItemIdentifier
      )
      let fitting = fittingHeight(of: panes.selected)
      let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
      let available =
        (window.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
      let size = SettingsWindowPane.contentSize(
        fittingHeight: fitting,
        availableHeight: available - chrome
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
