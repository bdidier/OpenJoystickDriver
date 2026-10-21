import Testing

@testable import OpenJoystickDriverPresentation

struct MenuBarSummaryTests {
  @Test
  @MainActor
  func menuBarPublishesOneCombinedSummaryWithASemanticSignal() {
    let runtime = RuntimeViewModel(gateway: GatewayStub())
    let menuBar = MenuBarViewModel(runtime: runtime)

    #expect(menuBar.summarySemanticState == .loading)
    #expect(menuBar.summaryTitle.split(separator: "·").count == 3)
  }
}
