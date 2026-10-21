import AppKit
import Foundation
import OpenJoystickDriverKit

/// Counts service status changes and holds waiters until the count moves.
///
/// The count follows `.ojdServiceStatusDidChange`, which the device manager, the permission
/// manager, the virtual output backends, the device pipelines (including an overdue input report)
/// and the remapping handlers post when what `getStatus` or the remapping snapshot reports
/// changes. The foreground application, which decides remapping eligibility, is observed here
/// through the workspace.
/// - Note: `@unchecked Sendable` because `generation` and `waiters` are guarded by `lock`.
final class ServiceStatusChanges: @unchecked Sendable {
  private final class Waiter {
    let continuation: CheckedContinuation<ServiceStatusRevision, Never>
    var hold: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<ServiceStatusRevision, Never>) {
      self.continuation = continuation
    }
  }

  private let lock = NSLock()
  private let instance: UUID
  private var generation: UInt64 = 0
  private var waiters: [UUID: Waiter] = [:]
  private let center: NotificationCenter
  private let workspaceCenter: NotificationCenter
  private var observers: [NSObjectProtocol] = []

  init(
    center: NotificationCenter = .default,
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    instance: UUID = UUID()
  ) {
    self.center = center
    self.workspaceCenter = workspaceCenter
    self.instance = instance
    observers = [
      center.addObserver(forName: .ojdServiceStatusDidChange, object: nil, queue: nil) {
        [weak self] _ in self?.recordChange()
      }
    ]
    observers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.recordChange() }
    )
  }

  deinit {
    for observer in observers {
      center.removeObserver(observer)
      workspaceCenter.removeObserver(observer)
    }
  }

  /// Returns the current revision at once when `after` is nil or differs from it, including by
  /// service instance; otherwise waits for the next change and returns the current revision after
  /// `holdSeconds` with none. A cancelled wait returns at once.
  func wait(after: ServiceStatusRevision?, holdSeconds: TimeInterval) async -> ServiceStatusRevision
  {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let waiter = Waiter(continuation)
        let current = lock.withLock { () -> ServiceStatusRevision? in
          let revision = ServiceStatusRevision(instance: instance, generation: generation)
          guard let after, after == revision, !Task.isCancelled else { return revision }
          waiters[id] = waiter
          return nil
        }
        if let current {
          continuation.resume(returning: current)
          return
        }
        let hold = Task { [weak self] in
          try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
          self?.release(id)
        }
        let answered = lock.withLock { () -> Bool in
          guard waiters[id] === waiter else { return true }
          waiter.hold = hold
          return false
        }
        if answered { hold.cancel() }
      }
    } onCancel: {
      release(id)
    }
  }

  private func recordChange() {
    let (released, revision) = lock.withLock { () -> ([Waiter], ServiceStatusRevision) in
      generation &+= 1
      defer { waiters = [:] }
      return (
        Array(waiters.values), ServiceStatusRevision(instance: instance, generation: generation)
      )
    }
    for waiter in released {
      waiter.hold?.cancel()
      waiter.continuation.resume(returning: revision)
    }
  }

  private func release(_ id: UUID) {
    let (waiter, revision) = lock.withLock {
      (
        waiters.removeValue(forKey: id),
        ServiceStatusRevision(instance: instance, generation: generation)
      )
    }
    waiter?.hold?.cancel()
    waiter?.continuation.resume(returning: revision)
  }
}
