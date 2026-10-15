import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

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

  /// The endpoint opens a gamepad for a persona id the policy can decide, and for no other.
  @Test(arguments: ServingFixture.all)
  func theEndpointAcceptsEveryPersonaThePolicyDecides(_ fixture: ServingFixture) {
    guard case .virtualHid(let persona) = fixture.route else { return }
    #expect(VirtualHIDProfileID(rawValue: persona.rawValue) == persona, "\(fixture.name)")
    #expect(VirtualHIDProfileID.allCases.map(\.rawValue).sorted() == ["Generic", "SdlCompatible"])
  }
}
