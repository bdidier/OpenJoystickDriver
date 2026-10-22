import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
@Suite
struct SettingsWindowPaneModelTests {
  @Test
  func panesAreInToolbarOrder() {
    #expect(
      SettingsWindowPaneModel().panes == [.general, .notifications, .advanced]
    )
  }

  @Test
  func theTitleKeyFollowsTheSelectedPane() {
    let model = SettingsWindowPaneModel()
    #expect(model.titleKey == "ui.settings.general.title")
    model.select(.notifications)
    #expect(model.titleKey == "ui.settings.notifications.title")
    #expect(model.selectedIndex == 1)
  }

  @Test
  func selectingByIndexRejectsAPositionOutsideThePanes() {
    let model = SettingsWindowPaneModel()
    #expect(model.select(index: 2))
    #expect(model.selected == .advanced)
    #expect(!model.select(index: 3))
    #expect(!model.select(index: -1))
    #expect(model.selected == .advanced)
  }

  @Test
  func everyPaneHasASymbolAndAccessibilityLabel() {
    for pane in SettingsWindowPane.allCases {
      #expect(!pane.symbolName.isEmpty)
      #expect(pane.accessibilityKey == "a11y.settingsPane.\(pane.rawValue)")
    }
  }

  @Test
  func everyPaneSharesOneWidthAndTheHeightFollowsTheContent() {
    let short = SettingsWindowPane.contentSize(fittingHeight: 300, availableHeight: 900)
    let tall = SettingsWindowPane.contentSize(fittingHeight: 600, availableHeight: 900)
    #expect(short.width == SettingsWindowPane.contentWidth)
    #expect(tall.width == short.width)
    #expect(short.height == 300)
    #expect(tall.height == 600)
  }

  @Test
  func aPaneTallerThanTheScreenIsCappedAndScrolls() {
    let size = SettingsWindowPane.contentSize(fittingHeight: 2_000, availableHeight: 700)
    #expect(size.height == 700)
  }

  @Test
  func aSmallerScreenCapsAPaneThatFitsALargerOne() {
    let chrome = 52.0
    let large = SettingsWindowPane.availableContentHeight(
      visibleHeight: 1_000,
      chromeHeight: chrome
    )
    let small = SettingsWindowPane.availableContentHeight(visibleHeight: 600, chromeHeight: chrome)

    let onLarge = SettingsWindowPane.contentSize(fittingHeight: 700, availableHeight: large)
    let onSmall = SettingsWindowPane.contentSize(fittingHeight: 700, availableHeight: small)

    #expect(onLarge.height == 700)
    #expect(onSmall.height == 600 - chrome - SettingsWindowPane.screenMargin)
  }

  @Test
  func aPaneKeepsAMinimumHeight() {
    let size = SettingsWindowPane.contentSize(fittingHeight: 0, availableHeight: 700)
    #expect(size.height == SettingsWindowPane.minimumContentHeight)
  }

  @Test
  func toolbarIdentifiersAreUniqueAndRoundTrip() {
    let identifiers = SettingsWindowPane.allCases.map(\.toolbarItemIdentifier)
    #expect(Set(identifiers).count == SettingsWindowPane.allCases.count)
    for pane in SettingsWindowPane.allCases {
      #expect(SettingsWindowPane(toolbarItemIdentifier: pane.toolbarItemIdentifier) == pane)
    }
    #expect(SettingsWindowPane(toolbarItemIdentifier: "NSToolbarSpaceItem") == nil)
  }
}
