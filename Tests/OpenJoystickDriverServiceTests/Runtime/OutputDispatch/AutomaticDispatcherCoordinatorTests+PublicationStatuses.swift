import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension AutomaticDispatcherCoordinatorTests {
  @Test(.timeLimit(.minutes(1)))
  func publicationStatusesReportPublishedThenFailedWithTheFailureText() async throws {
    // A recovery delay this long keeps the failed state until the coordinator closes.
    let coordinator = AutomaticDispatcherCoordinator(recoveryDelayNanoseconds: 3_600_000_000_000)
    let backend = InstallationBackend(stage: .none, gate: InstallationGate())
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    try #require(lease != nil)
    await lease?.release()

    let published = try #require(await coordinator.publicationStatuses()[identifier])
    #expect(published.state == .published)
    #expect(published.target == .generic)
    #expect(published.reason == nil && published.failure == nil)

    await coordinator.recoverPublication(
      for: identifier,
      failure: UserSpaceOutputDispatcher.CreationError.createFailed
    )

    let failed = try #require(await coordinator.publicationStatuses()[identifier])
    #expect(failed.state == .failed)
    #expect(
      failed.failure == String(describing: UserSpaceOutputDispatcher.CreationError.createFailed)
    )
    #expect(failed.reason == nil)
    #expect(failed.target == .generic)
    await coordinator.close()
  }
}
