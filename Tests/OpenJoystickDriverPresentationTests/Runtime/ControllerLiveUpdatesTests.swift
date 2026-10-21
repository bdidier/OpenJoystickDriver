import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ControllerLiveUpdatesTests {
  @Test
  func aServiceNotificationRefreshesWithinOneSecond() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let updates = ControllerLiveUpdates(
      source: source,
      log: { _ in },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }
    source.answer(1)
    await refreshed.waitUntil(1, timeout: 0.2)
    #expect(updates.mode == .subscribed)
    #expect(refreshed.value == 0)

    let clock = ContinuousClock()
    let start = clock.now
    source.answer(2)
    await refreshed.waitUntil(1, timeout: 1)

    #expect(refreshed.value == 1)
    #expect(clock.now - start < .seconds(1))
  }

  @Test
  func anUnavailableSubscriptionPollsAndLogsTheNamedFallbackOnce() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let updates = ControllerLiveUpdates(
      source: source,
      fallbackPollSeconds: 0.02,
      log: { logged.lines.append($0) },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }

    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(1, timeout: 1)
    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(2, timeout: 1)

    #expect(updates.mode == .polling(reason: ScriptedFailure.unreachable.localizedDescription))
    #expect(logged.lines.count == 1)
    #expect(logged.lines.first?.contains("polling") == true)
  }

  @Test
  func aRestoredSubscriptionStopsPollingAndRefreshesOnce() async {
    let source = ScriptedChangeSource()
    let refreshed = Counter()
    let logged = LogLines()
    let updates = ControllerLiveUpdates(
      source: source,
      fallbackPollSeconds: 0.02,
      log: { logged.lines.append($0) },
      refresh: { refreshed.increment() }
    )
    updates.start()
    defer { updates.stop() }
    source.fail(ScriptedFailure.unreachable)
    await refreshed.waitUntil(1, timeout: 1)

    source.answer(5)
    await refreshed.waitUntil(2, timeout: 1)

    #expect(updates.mode == .subscribed)
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

/// A change source whose waits finish only when the test answers or fails them.
private final class ScriptedChangeSource: ControllerChangeSource, @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [CheckedContinuation<UInt64, Error>] = []
  private var queued: [Result<UInt64, Error>] = []

  func waitForChange(after generation: UInt64?) async throws -> UInt64 {
    try await withCheckedThrowingContinuation { continuation in
      let ready = lock.withLock { () -> Result<UInt64, Error>? in
        if queued.isEmpty {
          pending.append(continuation)
          return nil
        }
        return queued.removeFirst()
      }
      if let ready { continuation.resume(with: ready) }
    }
  }

  func answer(_ generation: UInt64) { deliver(.success(generation)) }
  func fail(_ error: Error) { deliver(.failure(error)) }

  private func deliver(_ result: Result<UInt64, Error>) {
    let waiting = lock.withLock { () -> CheckedContinuation<UInt64, Error>? in
      if pending.isEmpty {
        queued.append(result)
        return nil
      }
      return pending.removeFirst()
    }
    waiting?.resume(with: result)
  }
}
