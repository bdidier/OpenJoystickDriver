#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  /// Carries a status-item action through `NSMenuItem.representedObject`.
  final class StatusItemActionBox: NSObject {
    let action: StatusItemAction

    init(_ action: StatusItemAction) { self.action = action }
  }

  /// Reports when the status menu opens and closes so it is refreshed on opening and never
  /// replaced while it is showing.
  @MainActor
  final class StatusMenuTracker: NSObject, NSMenuDelegate {
    private(set) var isOpen = false
    var onWillOpen: () -> Void = {}
    var onDidClose: () -> Void = {}

    func menuWillOpen(_ menu: NSMenu) {
      isOpen = true
      onWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
      isOpen = false
      onDidClose()
    }
  }

  extension MenuBarCoordinator {
    /// Builds the status menu from the model.
    func makeStatusMenu(from entries: [StatusItemEntry], title: String) -> NSMenu {
      let menu = NSMenu(title: title)
      menu.autoenablesItems = false
      for entry in entries { menu.addItem(makeMenuItem(for: entry)) }
      return menu
    }

    private func makeMenuItem(for entry: StatusItemEntry) -> NSMenuItem {
      if entry.isSeparator { return .separator() }
      let title: String
      switch entry.title {
      case .key(let key):
        title = MainMenuRenderer.title(key, appName: OJDLocalized.string("app.name"))
      case .verbatim(let text): title = text
      }
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.isEnabled = entry.isEnabled
      item.state = entry.isChecked ? .on : .off
      if let symbolName = entry.symbolName { item.image = menuImage(symbol: symbolName) }
      if let submenu = entry.submenu {
        item.submenu = makeStatusMenu(from: submenu, title: title)
      } else if let action = entry.action {
        item.target = self
        item.action = #selector(performStatusItemAction(_:))
        item.representedObject = StatusItemActionBox(action)
        if action == .showSettings {
          item.keyEquivalent = ","
          item.keyEquivalentModifierMask = [.command]
        } else if action == .quit {
          item.keyEquivalent = "q"
          item.keyEquivalentModifierMask = [.command]
        }
      }
      return item
    }

    @objc
    func performStatusItemAction(_ sender: Any?) {
      guard let box = (sender as? NSMenuItem)?.representedObject as? StatusItemActionBox else {
        return
      }
      switch box.action {
      case .suspendController(let token):
        runControllerAction(token) { device in await self.viewModel.suspendController(device) }
      case .resumeController(let token):
        runControllerAction(token) { device in await self.viewModel.resumeController(device) }
      case .testInput(let token): mainWindow?.showInputTest(controllerID: token)
      case .showController(let token): mainWindow?.showController(id: token)
      case .disconnectWireless(let token): disconnectWirelessController(sessionToken: token)
      case .activateProfile(let id):
        if let operation = confirmedActivation(of: id) { changeProfile(operation) }
      case .deactivateProfile(let id): changeProfile(.deactivate(profileID: id))
      case .showArea(let area): mainWindow?.showMainWindow(area: area)
      case .openWindow: mainWindow?.showMainWindow(area: nil)
      case .showSettings: settingsWindow?.showSettings(pane: nil)
      case .explainErrorCode: mainWindow?.showErrorCodeExplainer()
      case .openProjectWebsite: open(urlString: StatusItemModel.projectWebsite)
      case .openProblemReport: open(urlString: StatusItemModel.problemReport)
      case .quit: NSApplication.shared.terminate(sender)
      }
    }

    func open(urlString: String) {
      guard let url = URL(string: urlString) else { return }
      NSWorkspace.shared.open(url)
    }

    private func runControllerAction(
      _ sessionToken: String,
      _ action: @escaping @MainActor (ApplicationServiceDeviceDescription) async -> Void
    ) {
      guard
        let device = menuBarViewModel.devices.first(where: {
          $0.sessionToken.rawValue == sessionToken
        })
      else { return }
      Task { @MainActor in
        await action(device)
        if let failure = viewModel.controllerActionFailures[sessionToken] {
          presentFailure(failure)
        }
      }
    }

    private func disconnectWirelessController(sessionToken: String) {
      guard
        let device = menuBarViewModel.devices.first(where: {
          $0.sessionToken.rawValue == sessionToken
        })
      else { return }
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string("controllers.disconnectWirelessConfirmTitle")
      alert.informativeText = OJDLocalized.formatted(
        "controllers.disconnectWirelessConfirmMessage",
        device.name
      )
      alert.addButton(withTitle: OJDLocalized.string("controllers.disconnectWirelessConfirm"))
      alert.addButton(withTitle: OJDLocalized.string("common.cancel"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      runControllerAction(sessionToken) { device in
        await self.viewModel.disconnectWirelessController(device)
      }
    }

    /// The activation of a profile, after asking about a profile that produces no output; nil when
    /// the person declines.
    func confirmedActivation(of profileID: UUID) -> StatusItemProfileOperation? {
      let profiles: [RemappingProfile]
      if case .available(let snapshot) = viewModel.remappingState {
        profiles = snapshot.profiles
      } else {
        profiles = []
      }
      return StatusItemProfileOperation.activation(of: profileID, in: profiles) { _ in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = OJDLocalized.string("profiles.emptyActivationTitle")
        alert.informativeText = OJDLocalized.string("profiles.emptyActivationMessage")
        alert.addButton(withTitle: OJDLocalized.string("common.setActive"))
        alert.addButton(withTitle: OJDLocalized.string("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
      }
    }

    private func changeProfile(_ operation: StatusItemProfileOperation) {
      Task { @MainActor in
        guard let mainWindow else { return }
        let outcome = await operation.perform(on: mainWindow)
        guard let outcome else {
          presentFailure(OJDLocalized.string("menuBar.profileEditorBusy"))
          return
        }
        switch outcome.result {
        case .succeeded: return
        case .failed(_, _, let message), .rejected(_, _, let message): presentFailure(message)
        case .conflict:
          presentFailure(outcome.lastError ?? OJDLocalized.string("menuBar.profileConflict"))
        }
      }
    }

    private func presentFailure(_ message: String) {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string("menuBar.actionFailedTitle")
      alert.informativeText = message
      alert.addButton(withTitle: OJDLocalized.string("common.ok"))
      alert.runModal()
    }

    func menuImage(symbol: String) -> NSImage? {
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      image?.isTemplate = true
      return image
    }
  }

#endif
