import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Mapped physical output reaching the device manager through its `OutputSink` conformance.
extension PhysicalOutputExecutorTests {
  /// A release through the sink drops the remapping claim and writes the released channel.
  @Test
  func aReleaseThroughTheSinkReleasesTheMappingClaims() async throws {
    let started = try await startSixaxis(locationID: 540)
    let manager = started.manager
    let claim = MappingOutputClaim(
      .rumble(motor: .leftMain, intensity: 0.5),
      active: true,
      owner: UUID()
    )
    try await manager.consume(claim, for: started.identifier)
    let before = await started.backend.recordedOutputReports().count

    try await manager.consume(MappingOutputRelease(), for: started.identifier)

    let written = await started.backend.recordedOutputReports().dropFirst(before).map(sixaxisFields)
    #expect(written.map(\.rumble) == [[0, 0]])
    await manager.stop()
  }

  /// A profile colour through the sink is accepted, and refused once the manager is stopping.
  @Test
  func aProfileColorThroughTheSinkIsRefusedOnceTheManagerStops() async throws {
    let started = try await startSixaxis(locationID: 541)
    let manager = started.manager
    try await manager.consume(ProfileColorClaim(nil), for: started.identifier)
    await manager.stop()

    await #expect(
      throws: StreamBoundaryError.rejected(.physicalOutput, "profile colour not applied")
    ) {
      try await manager.consume(ProfileColorClaim(nil), for: started.identifier)
    }
  }
}
