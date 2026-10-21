import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.timeLimit(.minutes(1)))
struct ServiceStatusChangesTests {
  private static func revision(_ changes: ServiceStatusChanges) async -> ServiceStatusRevision {
    await changes.wait(after: nil, holdSeconds: 30)
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
    let changes = ServiceStatusChanges(center: NotificationCenter(), instance: instance)

    #expect(
      await changes.wait(after: nil, holdSeconds: 30)
        == ServiceStatusRevision(instance: instance, generation: 0)
    )
  }

  @Test
  func aWaitReturnsWithinOneSecondOfAStatusNotification() async {
    let center = NotificationCenter()
    let changes = ServiceStatusChanges(center: center)
    let baseline = await Self.revision(changes)
    let clock = ContinuousClock()

    let start = clock.now
    async let next = changes.wait(after: baseline, holdSeconds: 30)
    await Self.waitForHeldWaits(1, in: changes)
    center.post(name: .ojdServiceStatusDidChange, object: nil)

    #expect(await next.generation == 1)
    #expect(clock.now - start < .seconds(10))
  }

  @Test
  func aChangeBeforeTheWaitAnswersAtOnce() async {
    let center = NotificationCenter()
    let changes = ServiceStatusChanges(center: center)
    let baseline = await Self.revision(changes)
    center.post(name: .ojdServiceStatusDidChange, object: nil)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).generation == 1)
  }

  @Test
  func aWaitWithNoChangeReturnsTheSameRevisionAfterTheHoldTime() async {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)

    #expect(await changes.wait(after: baseline, holdSeconds: 0.05) == baseline)
  }

  @Test
  func aRestartedServiceDiffersEvenWithTheSameGeneration() async {
    let old = ServiceStatusRevision(instance: UUID(), generation: 0)
    let changes = ServiceStatusChanges(center: NotificationCenter(), instance: UUID())

    let revision = await changes.wait(after: old, holdSeconds: 30)

    #expect(revision.generation == old.generation)
    #expect(revision.instance != old.instance)
  }

  @Test
  func anApplicationActivationIsAStatusChange() async {
    let workspace = NotificationCenter()
    let changes = ServiceStatusChanges(center: NotificationCenter(), workspaceCenter: workspace)
    let baseline = await Self.revision(changes)

    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).generation == 1)
  }

  @Test
  func aCancelledWaitReturnsAtOnceWithoutWaitingForTheHoldTime() async {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    let clock = ContinuousClock()
    let start = clock.now
    let task = Task { await changes.wait(after: baseline, holdSeconds: 30) }
    task.cancel()

    #expect(await task.value == baseline)
    #expect(clock.now - start < .seconds(10))
  }

  @Test
  func theSharedPostAnnouncesAChange() async {
    let changes = ServiceStatusChanges(workspaceCenter: NotificationCenter())
    let baseline = await Self.revision(changes)

    NotificationCenter.postServiceStatusChanged(from: changes)

    #expect(await changes.wait(after: baseline, holdSeconds: 30).generation > baseline.generation)
  }
}
