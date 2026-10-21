import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.timeLimit(.minutes(1)))
struct ServiceStatusChangesTests {
  /// Changes that observe private centers only, so an application another process activates
  /// during the run is no status change here.
  private static func isolated(
    center: NotificationCenter = NotificationCenter(),
    instance: UUID = UUID()
  ) -> ServiceStatusChanges {
    ServiceStatusChanges(center: center, workspaceCenter: NotificationCenter(), instance: instance)
  }

  private static func revision(_ changes: ServiceStatusChanges) async -> ServiceStatusRevision {
    await changes.wait(after: nil, holdSeconds: 30).revision
  }

  /// Polls until `count` waits are held, for at most ten seconds.
  private static func waitForHeldWaits(_ count: Int, in changes: ServiceStatusChanges) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while changes.heldWaitCount < count, ContinuousClock.now < deadline {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(changes.heldWaitCount >= count)
  }

  @Test
  func aNilRevisionReadsTheCurrentOneAtOnce() async {
    let instance = UUID()
    let changes = Self.isolated(instance: instance)

    #expect(
      await changes.wait(after: nil, holdSeconds: 30)
        == ServiceStatusReply(
          revision: ServiceStatusRevision(instance: instance, generation: 0),
          event: .statusChange
        )
    )
  }

  @Test
  func aWaitReturnsWithinOneSecondOfAStatusNotification() async {
    let center = NotificationCenter()
    let changes = Self.isolated(center: center)
    let baseline = await Self.revision(changes)
    let clock = ContinuousClock()

    let start = clock.now
    async let next = changes.wait(after: baseline, holdSeconds: 30)
    await Self.waitForHeldWaits(1, in: changes)
    center.post(name: .ojdServiceStatusDidChange, object: nil)

    #expect(await next.revision.generation == 1)
    #expect(clock.now - start < .seconds(10))
  }

  @Test
  func aChangeBeforeTheWaitAnswersAtOnce() async {
    let center = NotificationCenter()
    let changes = Self.isolated(center: center)
    let baseline = await Self.revision(changes)
    center.post(name: .ojdServiceStatusDidChange, object: nil)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).revision.generation == 1)
  }

  @Test
  func aWaitWithNoChangeReturnsTheSameRevisionAfterTheHoldTime() async {
    let changes = Self.isolated()
    let baseline = await Self.revision(changes)

    #expect(
      await changes.wait(after: baseline, holdSeconds: 0.05)
        == ServiceStatusReply(revision: baseline, event: .holdElapsed)
    )
  }

  @Test
  func aRestartedServiceDiffersEvenWithTheSameGeneration() async {
    let old = ServiceStatusRevision(instance: UUID(), generation: 0)
    let changes = Self.isolated()

    let revision = await changes.wait(after: old, holdSeconds: 30).revision

    #expect(revision.generation == old.generation)
    #expect(revision.instance != old.instance)
  }

  @Test
  func anApplicationActivationIsAStatusChange() async {
    let workspace = NotificationCenter()
    let changes = ServiceStatusChanges(center: NotificationCenter(), workspaceCenter: workspace)
    let baseline = await Self.revision(changes)

    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).revision.generation == 1)
  }

  @Test
  func aCancelledWaitReturnsAtOnceWithoutWaitingForTheHoldTime() async {
    let changes = Self.isolated()
    let baseline = await Self.revision(changes)
    let clock = ContinuousClock()
    let start = clock.now
    let task = Task { await changes.wait(after: baseline, holdSeconds: 30) }
    task.cancel()

    #expect(await task.value.revision == baseline)
    #expect(clock.now - start < .seconds(10))
  }

  @Test
  func theSharedPostAnnouncesAChange() async {
    let changes = ServiceStatusChanges(workspaceCenter: NotificationCenter())
    let baseline = await Self.revision(changes)

    NotificationCenter.postServiceStatusChanged(from: changes)

    #expect(
      await changes.wait(after: baseline, holdSeconds: 30).revision.generation > baseline.generation
    )
  }

  @Test
  func aTestNotificationAnswersEveryHeldWaitWithoutMovingTheRevision() async {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    async let first = changes.wait(after: baseline, holdSeconds: 30)
    async let second = changes.wait(after: baseline, holdSeconds: 30)
    await Self.waitForHeldWaits(2, in: changes)

    #expect(changes.announceTestNotification() == 2)

    let expected = ServiceStatusReply(revision: baseline, event: .testNotification)
    #expect(await first == expected)
    #expect(await second == expected)
    #expect(changes.heldWaitCount == 0)
  }

  @Test
  func aTestNotificationWithNoHeldWaitAnnouncesToNobody() {
    let changes = ServiceStatusChanges(center: NotificationCenter())

    #expect(changes.announceTestNotification() == 0)
  }
}
