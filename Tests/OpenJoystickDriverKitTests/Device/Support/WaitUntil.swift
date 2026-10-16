import Foundation
import Testing

/// Suspends until `condition` holds. The condition is re-evaluated every millisecond with no
/// iteration limit, so passing does not depend on scheduling speed; the deadline only bounds a
/// condition that never becomes true and records it as a failure.
func waitUntil(
  _ description: String,
  deadline: Duration = .seconds(60),
  sourceLocation: SourceLocation = #_sourceLocation,
  _ condition: () async -> Bool
) async {
  let clock = ContinuousClock()
  let limit = clock.now.advanced(by: deadline)
  while !(await condition()) {
    guard clock.now < limit, !Task.isCancelled else {
      Issue.record("Condition never held: \(description)", sourceLocation: sourceLocation)
      return
    }
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
}
