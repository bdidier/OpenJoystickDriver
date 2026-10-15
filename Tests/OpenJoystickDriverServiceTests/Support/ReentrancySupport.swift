import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriverService

enum TransactionCompletion: Sendable {
  case accept
  case rollBack
}

actor RoutingCheckpointGate {
  private let checkpointToPause: RemappingRoutingCheckpoint
  private var armed = false
  private var paused = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(pausing checkpoint: RemappingRoutingCheckpoint) { checkpointToPause = checkpoint }

  func arm() { armed = true }

  func checkpoint(_ checkpoint: RemappingRoutingCheckpoint) async {
    guard armed, checkpoint == checkpointToPause else { return }
    armed = false
    paused = true
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilPaused() async { while !paused { await Task.yield() } }

  nonisolated func resume() { Task { await release() } }

  private func release() {
    continuation?.resume()
    continuation = nil
    paused = false
  }
}

actor AsyncCompletionProbe {
  private(set) var isFinished = false

  func finish() { isFinished = true }
}

final class BlockingReleaseSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private let releaseGate = DispatchSemaphore(value: 0)
  private var releaseBlocked = false
  private var recordedActions: [RemappingSystemInputAction] = []

  var actions: [RemappingSystemInputAction] { lock.withLock { recordedActions } }

  func send(_ action: RemappingSystemInputAction) throws {
    if action == .keyUp(.space) {
      lock.withLock { releaseBlocked = true }
      releaseGate.wait()
    }
    lock.withLock { recordedActions.append(action) }
  }

  func waitUntilReleaseIsBlocked() async {
    while !lock.withLock({ releaseBlocked }) { await Task.yield() }
  }

  func resumeRelease() { releaseGate.signal() }
}

final class TransientTerminalFailureSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private var sendCount = 0
  private var failingCalls: Set<Int>
  private var recordedActions: [RemappingSystemInputAction] = []

  init(failingCalls: Set<Int>) { self.failingCalls = failingCalls }

  var actions: [RemappingSystemInputAction] { lock.withLock { recordedActions } }

  func send(_ action: RemappingSystemInputAction) throws {
    try lock.withLock {
      sendCount += 1
      if failingCalls.remove(sendCount) != nil { throw TransientSinkError.rejected }
      recordedActions.append(action)
    }
  }

  private enum TransientSinkError: Error { case rejected }
}

/// Waits until `condition` holds and returns true.
///
/// The wait has no count or clock budget of its own, so whether it passes cannot depend on how
/// many scheduler turns the machine grants. A condition that never holds ends only when the
/// enclosing test's time limit cancels the task, and then the result is false.
func eventually(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
  while !condition() {
    if Task.isCancelled { return false }
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
  return true
}
