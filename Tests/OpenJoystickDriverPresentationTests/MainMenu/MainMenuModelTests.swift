import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainMenuModelTests {
  private func section(_ id: String) throws -> MainMenuSection {
    try #require(MainMenuModel.sections.first { $0.id == id })
  }

  @Test
  func menuSetIsTheFixedEight() {
    #expect(
      MainMenuModel.sections.map(\.id)
        == ["app", "file", "edit", "view", "controller", "profile", "window", "help"]
    )
  }

  @Test
  func itemIDsAreUnique() {
    let ids = MainMenuModel.allItems.map(\.id)
    #expect(Set(ids).count == ids.count)
  }

  @Test
  func everyItemHasATitleAnActionAndAGUICounterpart() {
    for item in MainMenuModel.allItems {
      #expect(!item.titleKey.isEmpty, "\(item.id) has no title key")
      #expect(MainMenuModel.item(for: item.action)?.id == item.id, "\(item.id) action is shared")
    }
  }

  @Test
  @MainActor
  func everyActionIsRoutedToExactlyOneHandler() {
    // A responder selector means AppKit performs it; otherwise the coordinator does.
    for item in MainMenuModel.allItems {
      let responder = MainMenuRenderer.responderSelector(for: item.action) != nil
      let isSystem = item.enabled == .responderChain
      if item.action == .services { continue }
      #expect(responder == isSystem, "\(item.id) routing and enabled rule disagree")
    }
  }

  @Test
  func guiCounterpartsFollowTheCoverageMatrix() throws {
    func counterpart(_ action: MainMenuAction) throws -> MainMenuGUICounterpart {
      try #require(MainMenuModel.item(for: action)).guiCounterpart
    }
    #expect(try counterpart(.importProfile) == .area(.profiles))
    #expect(try counterpart(.exportProfile) == .area(.profiles))
    #expect(try counterpart(.activateProfile) == .area(.profiles))
    #expect(try counterpart(.deactivateProfile) == .area(.profiles))
    #expect(try counterpart(.installRecordOrMod) == .area(.library))
    #expect(try counterpart(.saveSupportReport) == .area(.activity))
    #expect(try counterpart(.saveActivityLog) == .area(.activity))
    #expect(try counterpart(.suspendOrResumeController) == .area(.controllers))
    #expect(try counterpart(.testInput) == .area(.controllers))
    #expect(try counterpart(.disconnectWirelessLink) == .area(.controllers))
    #expect(try counterpart(.showControllerInWindow) == .area(.controllers))
    #expect(try counterpart(.settings) == .settingsPane(.general))
    #expect(try counterpart(.toggleSidebar) == .sidebarToolbarButton)
  }

  @Test
  func toolbarItemUsesOptionCommandTAndNamesWhatItWillDo() throws {
    let item = try #require(MainMenuModel.item(for: .toggleToolbar))
    #expect(item.keyEquivalent == "t")
    #expect(item.modifiers == [.command, .option])
    var state = MainMenuState()
    state.isToolbarVisible = true
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.hideToolbar")
    state.isToolbarVisible = false
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.showToolbar")
    let actions = try section("view").items.map(\.action)
    #expect(actions.suffix(3) == [.toggleToolbar, .toggleSidebar, .toggleFullScreen])
  }

  @Test
  func sidebarItemUsesControlCommandSAndNamesWhatItWillDo() throws {
    let item = try #require(MainMenuModel.item(for: .toggleSidebar))
    #expect(item.keyEquivalent == "s")
    #expect(item.modifiers == [.command, .control])
    var state = MainMenuState()
    state.isSidebarVisible = true
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.hideSidebar")
    state.isSidebarVisible = false
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.showSidebar")
  }

  @Test
  func profileAndInstallItemsPerformFlows() throws {
    for action in [
      MainMenuAction.importProfile, .exportProfile, .activateProfile, .installRecordOrMod,
    ] {
      #expect(action.performsFlow)
      #expect(MainMenuModel.item(for: action) != nil)
    }
    #expect(!MainMenuAction.showArea(.profiles).performsFlow)
    let export = try #require(MainMenuModel.item(for: .exportProfile))
    var exportState = MainMenuState(profileCount: 1, hasMainWindow: true)
    #expect(!MainMenuModel.isEnabled(export, state: exportState))
    exportState.hasSelectedProfile = true
    #expect(MainMenuModel.isEnabled(export, state: exportState))
    let activate = try #require(MainMenuModel.item(for: .activateProfile))
    #expect(!MainMenuModel.isEnabled(activate, state: MainMenuState()))
    #expect(MainMenuModel.isEnabled(activate, state: MainMenuState(profileCount: 1)))
  }

  @Test
  func appMenuHoldsTheStandardItems() throws {
    let actions = try section("app").items.map(\.action)
    #expect(actions == [.about, .settings, .services, .hide, .hideOthers, .showAll, .quit])
    let settings = try #require(MainMenuModel.item(for: .settings))
    #expect(settings.keyEquivalent == ",")
    #expect(settings.modifiers == [.command])
  }

  @Test
  func fileMenuHoldsTheCommandsAndTheStandardClose() throws {
    #expect(
      try section("file").items.map(\.action) == [
        .importProfile, .exportProfile, .installRecordOrMod, .close, .saveSupportReport,
        .saveActivityLog,
      ]
    )
    let close = try #require(MainMenuModel.item(for: .close))
    #expect(close.keyEquivalent == "w")
    #expect(close.modifiers == [.command])
    #expect(close.enabled == .responderChain)
  }

  @Test
  func editMenuHoldsTheStandardItemsInOrder() throws {
    #expect(
      try section("edit").items.map(\.action) == [
        .undo, .redo, .cut, .copy, .paste, .delete, .selectAll,
      ]
    )
    #expect(try #require(MainMenuModel.item(for: .delete)).keyEquivalent.isEmpty)
  }

  @Test
  func menusAppearInTheStandardOrder() {
    #expect(
      MainMenuModel.sections.map(\.id) == [
        "app", "file", "edit", "view", "controller", "profile", "window", "help",
      ]
    )
  }

  @Test
  func submenuParentsAndAreaOpeningItemsCarryNoEllipsis() throws {
    let withoutMoreInput: [MainMenuAction] = [
      .activateProfile, .testInput, .disconnectWirelessLink, .showActivityLog,
    ]
    for action in withoutMoreInput {
      let item = try #require(MainMenuModel.item(for: action))
      #expect(!OJDLocalized.string(item.titleKey).hasSuffix("..."), "\(item.titleKey)")
      #expect(!OJDLocalized.string(item.titleKey).hasSuffix("…"), "\(item.titleKey)")
    }
  }

  @Test
  func viewMenuHasSixAreasWithCommandDigits() throws {
    let items = try section("view").items
    let areaItems = items.filter {
      if case .showArea = $0.action { return true }
      return false
    }
    #expect(areaItems.map(\.action) == MainWindowArea.allCases.map { .showArea($0) })
    #expect(areaItems.map(\.keyEquivalent) == ["1", "2", "3", "4", "5"])
    #expect(areaItems.allSatisfy { $0.modifiers == [.command] })
    #expect(areaItems.map(\.titleKey) == MainWindowArea.allCases.map(\.titleKey))
    #expect(MainMenuModel.item(for: .toggleFullScreen) != nil)
  }

  @Test
  func controllerAndProfileItemsAreDisabledNeverHidden() throws {
    let state = MainMenuState()
    for id in ["controller", "profile"] {
      for item in try section(id).items {
        if item.action == .showControllerInWindow { continue }
        #expect(!MainMenuModel.isEnabled(item, state: state), "\(item.id) enabled without target")
      }
    }
  }

  @Test
  func controllerItemsFollowTheControllerState() throws {
    let wired = MainMenuControllerState(
      id: "a",
      name: "A",
      isSuspended: false,
      isWireless: false,
      hasActiveProfile: false
    )
    var state = MainMenuState(
      controllers: [wired],
      selectedControllerID: "a",
      profileCount: 1,
      hasMainWindow: true
    )
    let disconnect = try #require(MainMenuModel.item(for: .disconnectWirelessLink))
    let deactivate = try #require(MainMenuModel.item(for: .deactivateProfile))
    let activate = try #require(MainMenuModel.item(for: .activateProfile))
    let suspend = try #require(MainMenuModel.item(for: .suspendOrResumeController))
    #expect(!MainMenuModel.isEnabled(disconnect, state: state))
    #expect(!MainMenuModel.isEnabled(deactivate, state: state))
    #expect(MainMenuModel.isEnabled(activate, state: state))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.suspend")

    state.controllers = [
      MainMenuControllerState(
        id: "a",
        name: "A",
        isSuspended: true,
        isWireless: true,
        hasActiveProfile: true
      )
    ]
    #expect(MainMenuModel.isEnabled(disconnect, state: state))
    #expect(MainMenuModel.isEnabled(deactivate, state: state))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.resume")

    state.selectedControllerID = nil
    #expect(!MainMenuModel.isEnabled(suspend, state: state))
  }

  @Test
  func controllerMenuActsOnTheSelectedOfTwoControllers() throws {
    let first = MainMenuControllerState(
      id: "a",
      name: "First",
      isSuspended: false,
      isWireless: false,
      hasActiveProfile: false
    )
    let second = MainMenuControllerState(
      id: "b",
      name: "Second",
      isSuspended: true,
      isWireless: true,
      hasActiveProfile: true
    )
    var state = MainMenuState(
      controllers: [first, second],
      selectedControllerID: "a",
      profileCount: 1,
      hasMainWindow: true
    )
    let suspend = try #require(MainMenuModel.item(for: .suspendOrResumeController))
    let disconnect = try #require(MainMenuModel.item(for: .disconnectWirelessLink))
    let deactivate = try #require(MainMenuModel.item(for: .deactivateProfile))
    #expect(state.controller == first)
    #expect(MainMenuModel.controllerTargetTitle(state: state) == .verbatim("First"))
    #expect(MainMenuModel.isEnabled(suspend, state: state))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.suspend")
    #expect(!MainMenuModel.isEnabled(disconnect, state: state))
    #expect(!MainMenuModel.isEnabled(deactivate, state: state))

    state.selectedControllerID = "b"
    #expect(state.controller == second)
    #expect(MainMenuModel.controllerTargetTitle(state: state) == .verbatim("Second"))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.resume")
    #expect(MainMenuModel.isEnabled(disconnect, state: state))
    #expect(MainMenuModel.isEnabled(deactivate, state: state))
  }

  @Test
  func controllerTargetRowSaysWhyTheMenuIsDisabled() throws {
    let target = try #require(MainMenuModel.item(for: .controllerTarget))
    var state = MainMenuState()
    #expect(MainMenuModel.controllerTargetTitle(state: state) == .key("ui.controllers.emptyTitle"))
    #expect(!MainMenuModel.isEnabled(target, state: state))
    state.controllers = [
      MainMenuControllerState(
        id: "a",
        name: "A",
        isSuspended: false,
        isWireless: false,
        hasActiveProfile: false
      )
    ]
    state.selectedControllerID = "a"
    #expect(!MainMenuModel.isEnabled(target, state: state))
  }

  @Test
  func controllerTargetRowDistinguishesNoSelectionFromNoController() {
    var state = MainMenuState(
      controllers: [
        MainMenuControllerState(
          id: "a",
          name: "A",
          isSuspended: false,
          isWireless: false,
          hasActiveProfile: false
        )
      ]
    )
    #expect(
      MainMenuModel.controllerTargetTitle(state: state) == .key("ui.menu.controller.noneSelected")
    )
    state.selectedControllerID = "gone"
    #expect(state.controller == nil)
    #expect(
      MainMenuModel.controllerTargetTitle(state: state) == .key("ui.menu.controller.noneSelected")
    )
    state.controllers = []
    #expect(MainMenuModel.controllerTargetTitle(state: state) == .key("ui.controllers.emptyTitle"))
  }

  @Test
  @MainActor
  func controllerTargetRowTextIsTheNameOrLocalizedText() {
    #expect(MainMenuRenderer.text(of: .verbatim("Pad")) == "Pad")
    for key in ["ui.controllers.emptyTitle", "ui.menu.controller.noneSelected"] {
      let text = MainMenuRenderer.text(of: .key(key))
      #expect(!text.isEmpty && text != key, "\(key) has no text")
    }
  }

  @Test
  func theHelpMenuListsExplainErrorCodeAndReportProblemWithTheirCounterparts() throws {
    let help = try section("help")
    let explain = try #require(help.items.first { $0.action == .explainErrorCode })
    let report = try #require(help.items.first { $0.action == .reportProblem })
    #expect(explain.guiCounterpart == .area(.activity))
    #expect(report.guiCounterpart == .externalLink)
    #expect(!MainMenuModel.isEnabled(explain, state: MainMenuState()))
    #expect(MainMenuModel.isEnabled(explain, state: MainMenuState(hasMainWindow: true)))
    #expect(MainMenuModel.isEnabled(report, state: MainMenuState()))
  }

  @Test
  func saveItemsDoNotNeedAWindow() throws {
    let state = MainMenuState()
    for action in [MainMenuAction.saveSupportReport, .saveActivityLog, .copySupportReport] {
      let item = try #require(MainMenuModel.item(for: action))
      #expect(MainMenuModel.isEnabled(item, state: state))
    }
  }
}

@Suite
struct MainMenuRoutingTests {
  @Test
  @MainActor
  func submenuParentsCarryNoAction() {
    for item in MainMenuModel.allItems {
      switch MainMenuRenderer.routing(for: item.action) {
      case .services, .profileSubmenu:
        #expect(item.action == .services || item.action == .activateProfile)
      case .responder, .coordinator:
        #expect(item.action != .services && item.action != .activateProfile)
      case .informational:
        #expect(item.action == .controllerTarget)
        #expect(item.enabled == .never)
      }
    }
    if case .profileSubmenu = MainMenuRenderer.routing(for: .activateProfile) {
    } else {
      Issue.record("Activate Profile is not routed as a submenu parent")
    }
  }
}
