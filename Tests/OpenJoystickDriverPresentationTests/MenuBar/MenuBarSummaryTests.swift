import Testing

@testable import OpenJoystickDriverPresentation

struct MenuBarSummaryTests {
  @Test
  @MainActor
  func menuBarPublishesOneCombinedSummaryWithASemanticSignal() {
    let runtime = RuntimeViewModel(gateway: GatewayStub())
    let menuBar = MenuBarViewModel(runtime: runtime)

    #expect(menuBar.summarySemanticState == .loading)
    let title = menuBar.summaryTitle
    for part in [
      OJDLocalized.string("status.starting"),
      RuntimePresentation.deviceCountLabel(0),
      OJDLocalized.string("status.noActiveProfile"),
    ] {
      #expect(title.contains(part), "the summary \(title) lacks \(part)")
    }
  }
}
