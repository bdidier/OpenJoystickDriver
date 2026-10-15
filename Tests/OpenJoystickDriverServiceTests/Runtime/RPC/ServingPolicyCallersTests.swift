import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI
@testable import OpenJoystickDriverPresentation
@testable import OpenJoystickDriverService

struct ServingPolicyCallersTests {
  /// The service reports why nothing publishes from the route the policy decided, and publishes
  /// for exactly the routes that publish.
  @Test(arguments: ServingFixture.all)
  func theServiceReportsTheRouteThePolicyDecided(_ fixture: ServingFixture) {
    let route = ServingPolicy.route(
      for: fixture.device,
      outputEnabled: fixture.outputEnabled,
      override: fixture.override
    )
    #expect(route == fixture.route, "\(fixture.name)")
    let reason = ApplicationServiceServer.notPublishedReason(
      of: route,
      observation: fixture.observation
    )
    #expect((reason == nil) == route.publishesVirtualDevice, "\(fixture.name)")
  }

  /// What one caller says about a controller: the persona it shows and whether it offers the
  /// server choice.
  private struct Answer: Equatable {
    let persona: String?
    let offersServerChoice: Bool
  }

  /// Runs one fixture through the four callers' real entry points and compares their answers: the
  /// service's description (which the endpoint's controller stream also serves), the CLI's
  /// `virtual show` report and ownership check, and the GUI's persona and ownership picker.
  @MainActor
  @Test(arguments: ServingFixture.all)
  func theFourCallersGiveTheAnswerThePolicyDecided(_ fixture: ServingFixture) async throws {
    let id = LogicalControllerID(vendorID: 0x3537, productID: 0x100B)
    let server = try await VirtualOutputTests().profileOverrideServer(
      [id],
      outputEnabled: fixture.outputEnabled
    )
    if let override = fixture.override {
      try server.store.set(override, vendorID: 0x3537, productID: 0x100B)
    }
    defer { Task { await server.tearDown() } }

    // Service and endpoint: the description the service builds for its status and watch stream.
    let described = try #require(
      server.server.describingVirtualHIDProfiles([(id, fixture.device)]).first
    )
    let service = Answer(
      persona: described.virtualHIDProfile?.profile?.rawValue,
      offersServerChoice: ServingPolicy.offersServerChoice(ServingInput(described))
    )
    // CLI: the `virtual show` report and the `controller ownership` check.
    let cliAccepts =
      (try? ControllerOwnershipCommand.checkSupported(
        described,
        server: fixture.server,
        accessRoute: fixture.accessRoute
      )) != nil
    let cli = Answer(
      persona: VirtualShowReport.Controller(described).profile,
      offersServerChoice: cliAccepts
    )
    // GUI: the persona it shows and whether it shows the picker.
    let gui = Answer(
      persona: described.publishedVirtualProfile.flatMap { identity in
        VirtualHIDProfileID.allCases.first { $0.identity == identity }?.rawValue
      },
      offersServerChoice: ControllerOwnershipPicker.isShown(for: described)
    )

    let expected: String?
    switch fixture.route {
    case .virtualHid(let persona): expected = persona.rawValue
    case .extensionOwned: expected = VirtualHIDProfileID.default.rawValue
    case .nativePassThrough, .outputDisabled: expected = nil
    }
    let answer = Answer(persona: expected, offersServerChoice: fixture.offersServerChoice)
    #expect(service == answer, "\(fixture.name) service")
    #expect(cli == answer, "\(fixture.name) cli")
    #expect(gui == answer, "\(fixture.name) gui")
  }
}
