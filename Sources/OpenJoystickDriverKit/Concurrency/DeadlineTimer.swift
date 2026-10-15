import Foundation

/// Fires a handler once after a delay, on a thread that does not belong to the cooperative pool.
///
/// A deadline written as `Task.sleep` runs its expiry on the cooperative pool, so a pool whose
/// threads are all busy or blocked delivers the expiry late, and a deadline that exists to bound a
/// hung call is itself held up by the hang. Each timer here owns a serial dispatch queue, so its
/// expiry runs at once. Tests inject a manual timer to drive a deadline without real time.
package struct DeadlineTimer: Sendable {
  package typealias Cancel = @Sendable () -> Void
  package typealias Fire = @Sendable () -> Void

  /// Schedules `fire` after `nanoseconds` and returns a closure that cancels it.
  package let schedule: @Sendable (_ nanoseconds: UInt64, _ fire: @escaping Fire) -> Cancel

  package init(
    schedule: @escaping @Sendable (_ nanoseconds: UInt64, _ fire: @escaping Fire) -> Cancel
  ) {
    self.schedule = schedule
  }

  /// The timer production code uses: one dispatch timer on its own serial queue per deadline.
  package static let dispatch = Self { nanoseconds, fire in
    let queue = DispatchQueue(label: "com.openjoystickdriver.deadline")
    let source = DispatchSource.makeTimerSource(queue: queue)
    source.schedule(
      deadline: .now() + .nanoseconds(Int(clamping: nanoseconds)),
      leeway: .nanoseconds(0)
    )
    source.setEventHandler {
      source.cancel()
      fire()
    }
    source.resume()
    return { source.cancel() }
  }
}
