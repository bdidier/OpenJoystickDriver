import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// Task 24.5: `ojd controller show` prints the serving route and persona `ServingPolicy` decides.
struct ControllerShowServingTests {
  /// The fixture as the service describes it; a controller with output off reports why.
  private static func device(_ fixture: ServingFixture) -> ApplicationServiceDeviceDescription {
    var device = fixture.device
    if !fixture.outputEnabled {
      device.publication = ApplicationServicePublicationStatus(
        state: .notPublished,
        reason: "outputDisabled"
      )
    }
    return device
  }

  private static func show(_ fixture: ServingFixture, _ options: [String]) async throws -> CLIRun {
    let service = try FakeService(devices: [device(fixture)])
    return await service.run(["controller", "show", token("serving-fixture")] + options)
  }

  @Test(arguments: ServingFixture.all)
  func jsonCarriesTheRoutePersonaAndReasonOfThePolicy(_ fixture: ServingFixture) async throws {
    let decision = ServingPolicy.decision(ServingInput(Self.device(fixture)))
    let result = try await Self.show(fixture, ["--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let serving = try #require(try result.json()["serving"] as? [String: Any])
    #expect(serving["route"] as? String == decision.route.id, "\(fixture.name)")
    #expect(serving["persona"] as? String == decision.selection?.profileID.rawValue)
    #expect(serving["reason"] as? String == decision.route.disabledReason?.rawValue)
    // The route is the one the fixture names.
    #expect(decision.route.id == fixture.route.id, "\(fixture.name)")
  }

  @Test(arguments: ServingFixture.all)
  func plainAndHumanOutputNameTheRoute(_ fixture: ServingFixture) async throws {
    let decision = ServingPolicy.decision(ServingInput(Self.device(fixture)))
    let plain = try await Self.show(fixture, ["--plain"])
    let reason = decision.route.disabledReason?.rawValue ?? ""
    #expect(
      plain.standardOutput.contains("serving-route\t\(decision.route.id)\t\(reason)\n"),
      "\(fixture.name)"
    )
    let persona = decision.selection?.profileID.rawValue ?? ""
    #expect(plain.standardOutput.contains("persona\t\(persona)\n"), "\(fixture.name)")
    let human = try await Self.show(fixture, [])
    #expect(human.standardOutput.contains(decision.route.id), "\(fixture.name)")
  }

  @Test
  func everyRouteAppearsAcrossTheFixtures() {
    let ids = Set(ServingFixture.all.map(\.route.id))
    #expect(ids == ["NativePassThrough", "VirtualHid", "ExtensionOwned", "OutputDisabled"])
  }
}
