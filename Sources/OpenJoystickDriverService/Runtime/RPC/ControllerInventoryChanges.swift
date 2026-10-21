import Foundation
import OpenJoystickDriverKit

/// Counts controller inventory changes and holds waiters until the count moves.
///
/// The count follows `.ojdControllerInventoryDidChange`, which the device manager posts after an
/// attach, detach or session state change.
/// - Note: `@unchecked Sendable` because `generation` and `waiters` are guarded by `lock`.
final class ControllerInventoryChanges: @unchecked Sendable {
  private let lock = NSLock()
  private var generation: UInt64 = 0
  private var waiters: [UUID: CheckedContinuation<UInt64, Never>] = [:]
  private let center: NotificationCenter
  private var observer: NSObjectProtocol?

  init(center: NotificationCenter = .default) {
    self.center = center
    observer = center.addObserver(
      forName: .ojdControllerInventoryDidChange,
      object: nil,
      queue: nil
    ) { [weak self] _ in self?.recordChange() }
  }

  deinit { if let observer { center.removeObserver(observer) } }

  /// Returns the current generation at once when `after` is nil or differs from it; otherwise
  /// waits for the next change and returns the current generation after `holdSeconds` with none.
  func wait(after: UInt64?, holdSeconds: TimeInterval) async -> UInt64 {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let current = lock.withLock { () -> UInt64? in
          if let after, after == generation {
            waiters[id] = continuation
            return nil
          }
          return generation
        }
        if let current {
          continuation.resume(returning: current)
          return
        }
        Task { [weak self] in
          try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
          self?.release(id)
        }
      }
    } onCancel: {
      release(id)
    }
  }

  private func recordChange() {
    let (released, current) = lock.withLock {
      () -> ([UUID: CheckedContinuation<UInt64, Never>], UInt64) in
      generation &+= 1
      defer { waiters = [:] }
      return (waiters, generation)
    }
    for continuation in released.values { continuation.resume(returning: current) }
  }

  private func release(_ id: UUID) {
    let (continuation, current) = lock.withLock { (waiters.removeValue(forKey: id), generation) }
    continuation?.resume(returning: current)
  }
}
