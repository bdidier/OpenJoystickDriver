import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ServingPolicyTests {
  @Test(arguments: ServingFixture.all)
  func theFixtureSetGetsItsRoute(_ fixture: ServingFixture) {
    let first = ServingPolicy.route(fixture.input)
    let again = ServingPolicy.route(fixture.input)
    #expect(first == fixture.route, "\(fixture.name)")
    #expect(first == again)
  }

  @Test(arguments: ServingFixture.all)
  func aDescriptionGetsTheRouteOfItsInput(_ fixture: ServingFixture) {
    let route = ServingPolicy.route(
      for: fixture.device,
      outputEnabled: fixture.outputEnabled,
      override: fixture.override
    )
    #expect(route == fixture.route, "\(fixture.name)")
  }

  @Test
  func aRecordThatGivesANativeControllerToOJDTurnsPassThroughIntoAVirtualGamepad() {
    var input = ServingInput(observation: .systemGamepad)
    #expect(ServingPolicy.route(input) == .nativePassThrough(.none))
    input.server = .ojd
    #expect(ServingPolicy.route(input) == .virtualHID(.generic))
  }

  @Test
  func theDefaultPersonaIsGeneric() {
    #expect(VirtualHIDProfileID.default == .generic)
    #expect(ServingPolicy.route(ServingInput(observation: .exclusiveHID)) == .virtualHID(.generic))
  }

  @Test
  func onlySystemServedAndUpstreamOwnershipsPublishNothing() {
    for observation in ControllerOwnershipObservation.allCases {
      let publishes = ServingPolicy.route(ServingInput(observation: observation))
        .publishesVirtualDevice
      let expected = !observation.isServedBySystem && observation != .upstreamVirtualDevice
      #expect(publishes == expected, "\(observation)")
    }
  }

  @Test
  func duplicateRiskFollowsTheObservation() {
    #expect(DuplicateExposureRisk(observation: .systemHIDVisible) == .systemHIDVisible)
    #expect(DuplicateExposureRisk(observation: .systemGamepad) == DuplicateExposureRisk.none)
    #expect(DuplicateExposureRisk(observation: .upstreamVirtualDevice) == .upstreamVirtualDevice)
    #expect(DuplicateExposureRisk(observation: .unknown) == .unknownOwnership)
    #expect(DuplicateExposureRisk(observation: .exclusiveHID) == DuplicateExposureRisk.none)
  }

  @Test
  func systemServedOwnershipsAreExactlyTheNativeOnes() {
    let served: Set<ControllerOwnershipObservation> = [.systemGamepad, .systemHIDVisible]
    for observation in ControllerOwnershipObservation.allCases {
      #expect(observation.isServedBySystem == served.contains(observation), "\(observation)")
    }
  }
}
