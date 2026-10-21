import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowAreaTests {
  @Test
  func areasRunInToolbarOrderWithCommandDigits() {
    #expect(
      MainWindowArea.allCases == [.status, .controllers, .profiles, .library, .access, .activity]
    )
    #expect(MainWindowArea.allCases.map(\.keyEquivalent) == ["1", "2", "3", "4", "5", "6"])
  }

  @Test
  func everyAreaHasATitleAndAnAccessibilityKey() {
    for area in MainWindowArea.allCases {
      #expect(area.titleKey == "area.\(area.rawValue).title")
      #expect(area.accessibilityKey == "a11y.area.\(area.rawValue)")
    }
  }

  @Test
  func everyAreaSymbolExistsOnThisSystem() {
    for area in MainWindowArea.allCases {
      #expect(NSImage(systemSymbolName: area.symbolName, accessibilityDescription: nil) != nil)
    }
  }

  @Test
  @MainActor
  func commandThreeSelectsProfilesAndTheTitleFollows() {
    let navigation = MainWindowNavigationModel(persistence: MemoryAreaPersistence())
    let area = MainWindowArea.allCases.first { $0.keyEquivalent == "3" }
    #expect(area == .profiles)
    if let area { #expect(navigation.requestArea(area)) }
    #expect(navigation.selectedArea == .profiles)
    #expect(navigation.selectedArea.titleKey == "area.profiles.title")
  }

  @Test
  func sidebarToggleNamesWhatItWillDo() {
    #expect(
      MainWindowToolbarLayout.sidebarToggleTitleKey(sidebarCollapsed: true)
        == "mainWindow.showSidebar"
    )
    #expect(
      MainWindowToolbarLayout.sidebarToggleTitleKey(sidebarCollapsed: false)
        == "mainWindow.hideSidebar"
    )
  }

  @Test
  func toolbarHoldsTheSidebarToggleAndOneAreaGroup() {
    #expect(
      MainWindowToolbarLayout.items == [
        MainWindowToolbarLayout.sidebarToggle, .sidebarTrackingSeparator, .flexibleSpace,
        MainWindowToolbarLayout.areas, .flexibleSpace,
      ]
    )
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
