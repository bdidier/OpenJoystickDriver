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
          event: .firstRead
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

  private static func announcementID(_ reply: ServiceStatusReply) -> UUID? {
    guard reply.event == .testNotification else { return nil }
    return reply.announcement
  }

  @Test
  func aHeldWaitTakesTheAnnouncementAndTheReportEndsTheRequest() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    async let held = changes.wait(after: baseline, holdSeconds: 30)
    await Self.waitForHeldWaits(1, in: changes)

    async let outcome = changes.announceTestNotification()
    let reply = await held
    let id = try #require(Self.announcementID(reply))
    #expect(reply.revision == baseline)

    #expect(changes.reportTestNotification(id, outcome: .shown))
    #expect(await outcome == .shown)
    #expect(!changes.reportTestNotification(id, outcome: .denied))
  }

  @Test
  func anAnnouncementBetweenWaitsIsTakenByTheNextWait() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    let baseline = await Self.revision(changes)
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)

    let reply = await changes.wait(after: baseline, holdSeconds: 30)
    let id = try #require(Self.announcementID(reply))

    #expect(changes.reportTestNotification(id, outcome: .denied))
    #expect(await outcome == .denied)
  }

  @Test
  func aFailedReportCarriesTheReason() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    #expect(changes.reportTestNotification(id, outcome: .failed("no delivery")))
    #expect(await outcome == .failed("no delivery"))
  }

  @Test
  func noWaitBeforeThePickupDeadlineEndsWithNoAnswer() async {
    let changes = ServiceStatusChanges(center: NotificationCenter(), pickupSeconds: 0.05)

    #expect(await changes.announceTestNotification() == .noAnswer)
    let reply = await changes.wait(after: nil, holdSeconds: 30)
    #expect(reply.event == .firstRead)
  }

  @Test
  func aTakenAnnouncementWithNoReportEndsWithNoAnswer() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter(), answerSeconds: 0.05)
    async let outcome = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    _ = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    #expect(await outcome == .noAnswer)
  }

  @Test
  func aCancelledWaitEndsAsHoldElapsedAndDoesNotTakeTheAnnouncement() async {
    let changes = ServiceStatusChanges(center: NotificationCenter(), pickupSeconds: 0.05)
    let baseline = await Self.revision(changes)
    let cancelled = Task { await changes.wait(after: baseline, holdSeconds: 30) }
    cancelled.cancel()

    #expect(await cancelled.value.event == .holdElapsed)
    #expect(changes.heldWaitCount == 0)
    #expect(await changes.announceTestNotification() == .noAnswer)
  }

  @Test
  func aRequestWhileOneIsPendingJoinsIt() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter())
    async let first = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    async let second = changes.announceTestNotification()
    try await Task.sleep(nanoseconds: 20_000_000)
    let id = try #require(Self.announcementID(await changes.wait(after: nil, holdSeconds: 30)))

    #expect(changes.reportTestNotification(id, outcome: .shown))
    #expect(await first == .shown)
    #expect(await second == .shown)
  }

  @Test
  func aReportForAnAnnouncementNobodyTookIsRefused() async throws {
    let changes = ServiceStatusChanges(center: NotificationCenter(), pickupSeconds: 0.2)

    #expect(!changes.reportTestNotification(UUID(), outcome: .shown))
    #expect(await changes.announceTestNotification() == .noAnswer)
  }
}
