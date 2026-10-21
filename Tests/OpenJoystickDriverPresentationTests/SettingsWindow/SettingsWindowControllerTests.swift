import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
@MainActor
struct SettingsWindowControllerTests {
  private func controller(
    gateway: GatewayStub,
    developerTools: Bool = true
  ) throws -> (SettingsWindowController, SettingsPreferencesModel) {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.developerTools, to: developerTools)
    let preferences = SettingsPreferencesModel(
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )
    let controller = SettingsWindowController(
      gateway: gateway,
      runtime: RuntimeViewModel(gateway: gateway),
      preferences: preferences,
      commandLineTool: CommandLineToolModel()
    ) { _ in }
    return (controller, preferences)
  }

  private func gatedGateway() async -> GatewayStub {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    return gateway
  }

  private func startRead(_ controller: SettingsWindowController, _ gateway: GatewayStub) async {
    controller.showSettings(pane: .advanced)
    await gateway.waitForStatusCall(count: 1)
  }

  private func finishRead(_ controller: SettingsWindowController, _ gateway: GatewayStub) async {
    await gateway.resumeNextStatusRead()
    await waitUntil("the read ends") { !controller.developerTools.hasActiveOperation }
  }

  @Test
  func closingTheWindowDuringTheReadLeavesTheDiagnosticsNotLoaded() async throws {
    let gateway = await gatedGateway()
    let (controller, _) = try controller(gateway: gateway)
    await startRead(controller, gateway)

    controller.close()
    await finishRead(controller, gateway)

    #expect(controller.developerTools.loadState == .idle)
  }

  @Test
  func switchingPaneDuringTheReadLeavesTheDiagnosticsNotLoaded() async throws {
    let gateway = await gatedGateway()
    let (controller, _) = try controller(gateway: gateway)
    await startRead(controller, gateway)

    controller.showSettings(pane: .general)
    await finishRead(controller, gateway)

    #expect(controller.developerTools.loadState == .idle)
  }

  @Test
  func turningDeveloperToolsOffDuringTheReadLeavesTheDiagnosticsNotLoaded() async throws {
    let gateway = await gatedGateway()
    let (controller, preferences) = try controller(gateway: gateway)
    await startRead(controller, gateway)

    preferences.setDeveloperToolsEnabled(false)
    await waitUntil("the tools stop") { controller.developerTools.loadState == .idle }
    await finishRead(controller, gateway)

    #expect(controller.developerTools.loadState == .idle)
  }

  @Test
  func theCommandLineToolLinkIsReadWhenAdvancedIsShownNotWhenTheControllerIsMade() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SettingsWindowControllerTests.\(UUID().uuidString)"
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("App/OpenJoystickDriver")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data().write(to: executable)
    let link = CommandLineToolLink(
      linkURL: root.appendingPathComponent("bin/ojd"),
      executableURL: executable
    ) { _ in }
    let model = CommandLineToolModel(link: link)
    let gateway = GatewayStub()
    let controller = SettingsWindowController(
      gateway: gateway,
      runtime: RuntimeViewModel(gateway: gateway),
      preferences: SettingsPreferencesModel(
        settings: SettingsStore(directory: RootedDataDirectory.temporary()),
        launchAtLogin: LaunchAtLoginStub(isEnabled: false),
        notificationAuthorization: NotificationAuthorizationStub(state: .denied)
      ),
      commandLineTool: model
    ) { _ in }
    try link.install()
    #expect(model.status.state == .missing)

    controller.showSettings(pane: .advanced)
    controller.close()

    #expect(model.status.state == .installed)
  }
}
