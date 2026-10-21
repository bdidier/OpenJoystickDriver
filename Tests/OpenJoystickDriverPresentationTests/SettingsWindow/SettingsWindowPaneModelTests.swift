import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
@Suite
struct SettingsWindowPaneModelTests {
  @Test
  func panesAreInToolbarOrder() {
    #expect(
      SettingsWindowPaneModel().panes == [.general, .notifications, .commandLine, .advanced]
    )
  }

  @Test
  func theTitleKeyFollowsTheSelectedPane() {
    let model = SettingsWindowPaneModel()
    #expect(model.titleKey == "settingsPane.general.title")
    model.select(.notifications)
    #expect(model.titleKey == "settingsPane.notifications.title")
    #expect(model.selectedIndex == 1)
  }

  @Test
  func selectingByIndexRejectsAPositionOutsideThePanes() {
    let model = SettingsWindowPaneModel()
    #expect(model.select(index: 3))
    #expect(model.selected == .advanced)
    #expect(!model.select(index: 4))
    #expect(!model.select(index: -1))
    #expect(model.selected == .advanced)
  }

  @Test
  func everyPaneHasItsOwnMinimumSizeAndLabels() {
    for pane in SettingsWindowPane.allCases {
      let size = pane.minimumContentSize
      #expect(size.width >= 400 && size.height >= 200)
      #expect(!pane.symbolName.isEmpty)
      #expect(pane.accessibilityKey == "a11y.settingsPane.\(pane.rawValue)")
    }
    #expect(
      SettingsWindowPane.advanced.minimumContentSize.width
        > SettingsWindowPane.general.minimumContentSize.width
    )
  }
}
