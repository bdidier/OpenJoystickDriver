import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverPresentation

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ControllerLiveUpdatesTests {
  @Test
  func theFirstAnswerRefreshesOnceAndAServiceNotificationRefreshesWithinOneSecond() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = ControllerLiveUpdates(
      source: source,
      log: { _ in },
      modeChanged: { _ in },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    await refreshed.waitUntil(1, timeout: 1)
    #expect(updates.mode == .subscribed)
    #expect(refreshed.value == 1)

    let clock = ContinuousClock()
    let start = clock.now
    source.answer(.revision(2))
    await refreshed.waitUntil(2, timeout: 1)

    #expect(refreshed.value == 2)
    #expect(clock.now - start < .seconds(1))
  }

  @Test
  func aHoldTimeAnswerWithNoChangeStillRefreshesForTimeDerivedHealth() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = ControllerLiveUpdates(
      source: source,
      log: { _ in },
      modeChanged: { _ in },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }
    source.answer(.revision(1))
    source.answer(.revision(1))
    await refreshed.waitUntil(2, timeout: 1)

    #expect(refreshed.value == 2)
  }

  @Test
  func anUnavailableSubscriptionPollsAndLogsTheNamedFallbackOnce() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let modes = Modes()
    let updates = ControllerLiveUpdates(
      source: source,
      fallbackPollSeconds: 0.02,
      log: { logged.lines.append($0) },
      modeChanged: { modes.values.append($0) },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }

    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(1, timeout: 1)
    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(2, timeout: 1)

    let reason = ScriptedFailure.unreachable.localizedDescription
    #expect(updates.mode == .polling(reason: reason))
    #expect(modes.values == [.polling(reason: reason)])
    #expect(logged.lines.count == 1)
    #expect(logged.lines.first?.contains("polling every 0.02 s") == true)
  }

  @Test
  func aRestoredSubscriptionStopsPollingAndRefreshesOnce() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let modes = Modes()
    let updates = ControllerLiveUpdates(
      source: source,
      fallbackPollSeconds: 0.02,
      log: { logged.lines.append($0) },
      modeChanged: { modes.values.append($0) },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }
    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(1, timeout: 1)

    source.answer(.revision(5))
    await refreshed.waitUntil(2, timeout: 1)

    #expect(updates.mode == .subscribed)
    #expect(modes.values.last == .subscribed)
    #expect(logged.lines.count == 2)
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
  static func revision(_ generation: UInt64) -> Self {
    Self(
      instance: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      generation: generation
    )
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
