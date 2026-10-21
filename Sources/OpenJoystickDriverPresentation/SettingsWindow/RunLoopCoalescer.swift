import Foundation

/// Runs an action once for any number of `schedule()` calls made before the deferred turn runs.
@MainActor
final class RunLoopCoalescer {
  private let action: @MainActor () -> Void
  private let deferring: (@escaping @MainActor () -> Void) -> Void
  private var isScheduled = false

  /// - Parameters:
  ///   - deferring: runs its work on a later turn of the main run loop.
  ///   - action: what runs once per turn.
  init(
    deferring: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
      Task { @MainActor in work() }
    },
    action: @escaping @MainActor () -> Void
  ) {
    self.deferring = deferring
    self.action = action
  }

  func schedule() {
    guard !isScheduled else { return }
    isScheduled = true
    deferring { [self] in
      isScheduled = false
      action()
    }
  }
}
