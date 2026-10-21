import AppKit
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowAreaTests {
  @Test
  func areasRunInToolbarOrderWithCommandDigits() {
    #expect(MainWindowArea.allCases == [.controllers, .profiles, .library, .access, .activity])
    #expect(MainWindowArea.allCases.map(\.keyEquivalent) == ["1", "2", "3", "4", "5"])
  }

  @Test
  func everyAreaHasATitleKey() {
    for area in MainWindowArea.allCases {
      #expect(area.titleKey == "area.\(area.rawValue).title")
    }
  }

  @Test
  func onlyControllersProfilesAndLibraryHaveAListColumn() {
    #expect(MainWindowArea.allCases.filter(\.hasListColumn) == [.controllers, .profiles, .library])
  }

  @Test
  @MainActor
  func theWindowOpensOnControllersWhenNoAreaWasChosen() {
    let navigation = MainWindowNavigationModel(persistence: MemoryAreaPersistence())
    #expect(navigation.selectedArea == .controllers)
  }

  @Test
  @MainActor
  func commandTwoSelectsProfilesAndTheTitleFollows() {
    let navigation = MainWindowNavigationModel(persistence: MemoryAreaPersistence())
    let area = MainWindowArea.allCases.first { $0.keyEquivalent == "2" }
    #expect(area == .profiles)
    if let area { #expect(navigation.requestArea(area)) }
    #expect(navigation.selectedArea == .profiles)
    #expect(navigation.selectedArea.titleKey == "area.profiles.title")
  }

  @Test
  func toolbarHoldsTheSidebarToggleAndNoAreaSwitcher() {
    #expect(
      MainWindowToolbarLayout.fixedItems == [
        .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
      ]
    )
    for area in MainWindowArea.allCases {
      #expect(
        MainWindowToolbarLayout.items(for: area, activityMode: .log).starts(
          with: MainWindowToolbarLayout.fixedItems
        )
      )
    }
  }

  @Test
  func eachAreaShowsItsOwnActionsAfterTheFixedItems() {
    #expect(MainWindowArea.controllers.toolbarActions(activityMode: .log) == [.refreshControllers])
    #expect(
      MainWindowArea.profiles.toolbarActions(activityMode: .log) == [.newProfile, .importProfile]
    )
    #expect(MainWindowArea.library.toolbarActions(activityMode: .log) == [.installLibraryItem])
    #expect(MainWindowArea.access.toolbarActions(activityMode: .log).isEmpty)
    #expect(
      MainWindowToolbarLayout.items(for: .profiles, activityMode: .log)
        == MainWindowToolbarLayout.fixedItems + [
          MainWindowToolbarAction.newProfile.identifier,
          MainWindowToolbarAction.importProfile.identifier,
        ]
    )
  }

  @Test
  func activityActionsFollowTheViewItShows() {
    #expect(
      MainWindowArea.activity.toolbarActions(activityMode: .log) == [
        .activityMode, .activityFilter, .activitySearch, .copyActivityLog,
        .saveActivityLog, .showActivityLogInFinder,
      ]
    )
    #expect(
      MainWindowArea.activity.toolbarActions(activityMode: .diagnostics) == [
        .activityMode, .runDiagnostics,
      ]
    )
    #expect(
      MainWindowToolbarLayout.items(for: .activity, activityMode: .diagnostics)
        == MainWindowToolbarLayout.fixedItems + [
          MainWindowToolbarAction.activityMode.identifier,
          MainWindowToolbarAction.runDiagnostics.identifier,
        ]
    )
  }

  @Test
  func everyActionIsAllowedHasDistinctIdentifierAndLocalizedText() {
    let actions = MainWindowToolbarAction.allCases
    #expect(Set(actions.map(\.identifier)).count == actions.count)
    for action in actions {
      #expect(MainWindowToolbarAction(identifier: action.identifier) == action)
      #expect(MainWindowToolbarLayout.allowedItems.contains(action.identifier))
      #expect(NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil) != nil)
      #expect(OJDLocalized.string(action.labelKey) != action.labelKey)
      #expect(OJDLocalized.string(action.descriptionKey) != action.descriptionKey)
    }
  }

  @Test
  func onlyControllersHasASummaryLineWhileTheServiceIsUnavailable() {
    for area in MainWindowArea.allCases {
      #expect(MainWindowSummary.text(for: area, status: .loading).isEmpty)
    }
  }

  @Test
  func everyAreaSymbolExistsOnThisSystem() {
    for area in MainWindowArea.allCases {
      #expect(NSImage(systemSymbolName: area.symbolName, accessibilityDescription: nil) != nil)
    }
  }

  @Test
  func settingsPanesRunInToolbarOrder() {
    #expect(SettingsWindowPane.allCases == [.general, .notifications, .commandLine, .advanced])
  }
}

private final class MemoryAreaPersistence: MainWindowAreaPersistence {
  var area: MainWindowArea?
  func loadArea() -> MainWindowArea? { area }
  func saveArea(_ area: MainWindowArea) { self.area = area }
}
