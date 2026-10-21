import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  @Test
  func aUnitOverrideRetargetsOnlyThatUnitAndResettingItFallsBackToTheModel() async throws {
    let first = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
    let second = LogicalControllerID(vendorID: 1, productID: 2, locationID: 2)
    let fixture = try await profileOverrideServer([first, second])
    let automatic = fixture.server.automaticUserSpaceDispatcher()
    func live(_ identifier: LogicalControllerID) -> VirtualHIDProfileID? {
      automatic?.profileState(for: identifier).selection?.profileID
    }

    let set = await fixture.change(
      .set("SDLCompatible"),
      controller: .port(try #require(first.testPortKey)),
      unit: true
    )

    #expect(set.failure == nil)
    #expect(live(first) == .sdlCompatible)
    #expect(live(second) == .generic)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == nil)
    #expect(
      fixture.store.override(vendorID: 1, productID: 2, unit: first.testPortKey?.rawValue)
        == .sdlCompatible
    )

    let reset = await fixture.change(
      .reset,
      controller: .port(try #require(first.testPortKey)),
      unit: true
    )

    #expect(reset.failure == nil)
    #expect(live(first) == .generic)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func aUnitOverrideForAControllerWithoutAUnitIDIsNotFound() async throws {
    let fixture = try await profileOverrideServer()

    let result = await fixture.change(.set("SDLCompatible"), unit: true)

    #expect(result.failure == .controllerNotFound)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }
}
