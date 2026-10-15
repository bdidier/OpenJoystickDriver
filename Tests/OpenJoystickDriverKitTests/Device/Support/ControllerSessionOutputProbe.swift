import Foundation

@testable import OpenJoystickDriverKit

/// Deterministic uptime for liveness timing; it moves only when a test advances it.
final class ManualUptime: @unchecked Sendable {
  private let lock = NSLock()
  private var nanoseconds: UInt64 = 1_000_000_000

  var now: @Sendable () -> UInt64 { { [self] in lock.withLock { nanoseconds } } }

  func advance(by delta: UInt64) { lock.withLock { nanoseconds += delta } }
}

final class ControllerSessionOutputProbe: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var storedSuppression = false
  private var states: [ControllerState] = []
  private var stopped: [LogicalControllerID] = []

  var suppressOutput: Bool {
    get { lock.withLock { storedSuppression } }
    set { lock.withLock { storedSuppression = newValue } }
  }

  func dispatch(
    _ event: ControllerEvent,
    from _: LogicalControllerID
  ) { lock.withLock { states.append(event.state) } }

  func activateOutput(for _: LogicalControllerID) {}

  func controllerDidStop(_ identifier: LogicalControllerID) {
    lock.withLock { stopped.append(identifier) }
  }

  func snapshot() -> (states: [ControllerState], stopped: [LogicalControllerID]) {
    lock.withLock { (states, stopped) }
  }
}
