import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverPresentation

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ControllerLiveUpdatesTests {
  private func makeUpdates(
    _ source: ScriptedChangeSource,
    refreshed: Counter,
    logged: LogLines = LogLines(),
    modes: Modes = Modes()
  ) -> ControllerLiveUpdates {
    ControllerLiveUpdates(
      source: source,
      fallbackPollSeconds: 0.01,
      log: { logged.lines.append($0) },
      modeChanged: { modes.values.append($0) },
      refresh: { refreshed.increment() }
    )
  }

  @Test
  func theFirstAnswerRefreshesOnceAndAServiceNotificationRefreshesWithinOneSecond() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = makeUpdates(source, refreshed: refreshed)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    await refreshed.waitUntil(1, timeout: 30)
    #expect(updates.mode == .subscribed)
    #expect(refreshed.value == 1)

    source.answer(.revision(2))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(refreshed.value == 2)
  }

  @Test
  func aHoldTimeAnswerWithNoChangeRefreshesNothing() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = makeUpdates(source, refreshed: refreshed)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    source.answer(.revision(1))
    source.answer(.revision(2))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(refreshed.value == 2)
  }

  @Test
  func aRestartedServiceWithTheSameCountRefreshes() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = makeUpdates(source, refreshed: refreshed)
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(0))
    await refreshed.waitUntil(1, timeout: 30)
    source.answer(.revision(0, instance: "00000000-0000-0000-0000-000000000002"))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(refreshed.value == 2)
  }

  @Test
  func pollingIsLoggedOnceAndReportedOnlyAfterSeveralConsecutiveFailures() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, logged: logged, modes: modes)
    updates.start()
    defer { updates.stop() }

    for _ in 0..<(ControllerLiveUpdates.failuresBeforeReporting - 1) {
      source.fail(ScriptedFailure.unreachable)
    }
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting - 1, timeout: 30)
    #expect(modes.values.isEmpty)
    #expect(logged.lines.count == 1)
    #expect(logged.lines.first?.contains("polling every 0.01 s") == true)
    #expect(logged.lines.first?.contains("The service is unreachable.") == true)

    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting, timeout: 30)

    let expected = ControllerLiveUpdateMode.polling(
      failure: .other,
      detail: ScriptedFailure.unreachable.localizedDescription
    )
    #expect(updates.mode == expected)
    #expect(modes.values == [expected])
    #expect(logged.lines.count == 1)
  }

  @Test
  func aRecoveryBeforeTheThresholdNeverReportsPolling() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, logged: logged, modes: modes)
    updates.start()
    defer { updates.stop() }
    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(1, timeout: 30)
    source.answer(.revision(5))
    await refreshed.waitUntil(2, timeout: 30)

    #expect(updates.mode == .subscribed)
    #expect(modes.values.isEmpty)
    #expect(logged.lines.count == 2)
  }

  @Test
  func aRestoredWaitAfterAReportedFallbackIsReportedOnceAndRefreshes() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let modes = Modes()
    let updates = makeUpdates(source, refreshed: refreshed, modes: modes)
    updates.start()
    defer { updates.stop() }
    for _ in 0..<ControllerLiveUpdates.failuresBeforeReporting {
      source.fail(ScriptedFailure.unreachable)
    }
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting, timeout: 30)

    source.answer(.revision(5))
    await refreshed.waitUntil(ControllerLiveUpdates.failuresBeforeReporting + 1, timeout: 30)

    #expect(updates.mode == .subscribed)
    #expect(modes.values.last == .subscribed)
    #expect(modes.values.count == 2)
  }

  @Test
  func failuresMapToOneBannerReasonEach() {
    #expect(
      ControllerLiveUpdateFailure(LocalServiceRPCError.serviceClosedConnection)
        == .serviceClosedConnection
    )
    #expect(ControllerLiveUpdateFailure(ApplicationServiceClientError.timeout) == .timeout)
    #expect(ControllerLiveUpdateFailure(ScriptedFailure.unreachable) == .other)
    let keys = [
      ControllerLiveUpdateFailure.serviceClosedConnection, .timeout, .other,
    ].map(\.detailKey)
    #expect(Set(keys).count == 3)
    for key in keys { #expect(OJDLocalized.string(key) != key) }
  }
}

private enum ScriptedFailure: Error, LocalizedError {
  case unreachable
  var errorDescription: String? { "The service is unreachable." }
}

@MainActor
private final class Counter {
  private(set) var value = 0
  func increment() { value += 1 }

  func waitUntil(_ target: Int, timeout: Double) async {
    let deadline = Date().addingTimeInterval(timeout)
    while value < target, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
  }
}

@MainActor
private final class LogLines { var lines: [String] = [] }

@MainActor
private final class Modes { var values: [ControllerLiveUpdateMode] = [] }

extension ServiceStatusRevision {
  static func revision(
    _ generation: UInt64,
    instance: String = "00000000-0000-0000-0000-000000000001"
  ) -> Self {
    Self(instance: UUID(uuidString: instance)!, generation: generation)
  }
}

/// A change source whose waits finish only when the test answers or fails them.
private final class ScriptedChangeSource: ControllerChangeSource, @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [CheckedContinuation<ServiceStatusRevision, Error>] = []
  private var queued: [Result<ServiceStatusRevision, Error>] = []

  func waitForChange(after revision: ServiceStatusRevision?) async throws -> ServiceStatusRevision {
    try await withCheckedThrowingContinuation { continuation in
      let ready = lock.withLock { () -> Result<ServiceStatusRevision, Error>? in
        if queued.isEmpty {
          pending.append(continuation)
          return nil
        }
        return queued.removeFirst()
      }
      if let ready { continuation.resume(with: ready) }
    }
  }

  func answer(_ revision: ServiceStatusRevision) { deliver(.success(revision)) }
  func fail(_ error: Error) { deliver(.failure(error)) }

  private func deliver(_ result: Result<ServiceStatusRevision, Error>) {
    let waiting = lock.withLock { () -> CheckedContinuation<ServiceStatusRevision, Error>? in
      if pending.isEmpty {
        queued.append(result)
        return nil
      }
      return pending.removeFirst()
    }
    waiting?.resume(with: result)
  }
}
