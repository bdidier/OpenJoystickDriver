#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The pane the Settings window shows; SwiftUI content for the selected pane.
  private struct SettingsWindowContent: View {
    @ObservedObject
    var panes: SettingsWindowPaneModel
    let preferences: SettingsPreferencesModel
    let commandLineTool: CommandLineToolModel
    let developerTools: DeveloperToolsViewModel

    var body: some View {
      switch panes.selected {
      case .general: GeneralPaneView(preferences: preferences)
      case .notifications: NotificationsPaneView(preferences: preferences)
      case .commandLine: CommandLinePaneView(commandLineTool: commandLineTool)
      case .advanced:
        AdvancedPaneView(preferences: preferences, developerTools: developerTools)
      }
    }
  }

  /// The Settings window: toolbar buttons choose the pane, and the window title is the pane title.
  @MainActor
  final class SettingsWindowController: NSWindowController, NSWindowDelegate,
    SettingsWindowPresenting
  {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.SettingsToolbar"
    )
    private static let paneGroupIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.SettingsPanes"
    )

    private let panes: SettingsWindowPaneModel
    private let developerTools: DeveloperToolsViewModel
    private let visibilityChanged: @MainActor (Bool) -> Void
    private weak var paneGroup: NSToolbarItemGroup?

    /// - Parameters:
    ///   - gateway: the service connection the developer tools in Advanced read.
    ///   - preferences: the switches of General, Notifications and Advanced.
    ///   - commandLineTool: the command-line tool link of the Command Line pane.
    ///   - visibilityChanged: called with true when the window is shown and false when it closes.
    init(
      gateway: any ApplicationServiceGateway,
      preferences: SettingsPreferencesModel,
      commandLineTool: CommandLineToolModel,
      visibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
      self.visibilityChanged = visibilityChanged
      panes = SettingsWindowPaneModel()
      developerTools = DeveloperToolsViewModel(gateway: gateway)
      let content = SettingsWindowContent(
        panes: panes,
        preferences: preferences,
        commandLineTool: commandLineTool,
        developerTools: developerTools
      )
      let minimum = panes.minimumContentSize
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: minimum.width, height: minimum.height),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.hidesOnDeactivate = false
      window.contentView = NSHostingView(rootView: content)
      super.init(window: window)
      window.delegate = self
      configureToolbar(on: window)
      paneChanged()
      window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSettings(pane: SettingsWindowPane?) {
      if let pane {
        panes.select(pane)
        paneChanged()
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
      if #available(macOS 11.0, *) { window.toolbarStyle = .preference }
    }

    /// Sets the title of the selected pane and sizes the fixed-size window to the pane's size.
    private func paneChanged() {
      guard let window else { return }
      window.title = OJDLocalized.string(panes.titleKey)
      let minimum = panes.minimumContentSize
      let size = NSSize(width: minimum.width, height: minimum.height)
      window.contentMinSize = size
      if window.contentRect(forFrameRect: window.frame).size != size {
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
      }
      paneGroup?.selectedIndex = panes.selectedIndex
    }

    @objc
    private func paneButtonClicked(_ sender: NSToolbarItemGroup) {
      guard panes.select(index: sender.selectedIndex) else { return }
      paneChanged()
    }
  }

  extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.paneGroupIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.paneGroupIdentifier]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.paneGroupIdentifier]
    }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      guard itemIdentifier == Self.paneGroupIdentifier else { return nil }
      let titles = panes.panes.map { OJDLocalized.string($0.titleKey) }
      let group = NSToolbarItemGroup(
        itemIdentifier: itemIdentifier,
        titles: titles,
        selectionMode: .selectOne,
        labels: titles,
        target: self,
        action: #selector(paneButtonClicked(_:))
      )
      group.controlRepresentation = .expanded
      for (item, pane) in zip(group.subitems, panes.panes) {
        let label = OJDLocalized.string(pane.accessibilityKey)
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: label)
        item.toolTip = label
      }
      group.selectedIndex = panes.selectedIndex
      paneGroup = group
      return group
    }
  }

#endif
