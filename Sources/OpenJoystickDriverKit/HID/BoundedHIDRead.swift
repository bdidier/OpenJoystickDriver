import Foundation
import IOKit

/// Runs a synchronous HID read off the caller's actor and gives up after a deadline, so a device
/// that never answers cannot hold up the caller. `IOHIDDeviceGetReport` has no timeout of its
/// own, and a read that timed out keeps its thread until the system call returns. A device with
/// such a read outstanding is not read again: the next read fails at once with
/// `kIOReturnBusy`, so a silent device cannot pile up blocked threads.
final class BoundedHIDRead: Sendable {
  private let outstanding = Locked<Set<UUID>>([])
  private let scheduleDeadline: DeadlineScheduler

  typealias DeadlineScheduler = @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

  /// `scheduleDeadline` runs its action once `timeout` seconds have passed; tests replace it to
  /// observe the deadline a read is given.
  init(scheduleDeadline: @escaping DeadlineScheduler = BoundedHIDRead.dispatchAfter) {
    self.scheduleDeadline = scheduleDeadline
  }

  @Sendable
  private static func dispatchAfter(
    _ timeout: TimeInterval,
    _ action: @escaping @Sendable () -> Void
  ) {
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: action)
  }

  /// The outcome of `read` for the device `key`, a `kIOReturnTimeout` failure when it has not
  /// returned within `timeout` seconds, or a `kIOReturnBusy` failure, without calling `read`,
  /// while an earlier read of `key` has not returned.
  func run(
    key: UUID,
    timeout: TimeInterval,
    read: @escaping @Sendable () -> PhysicalHIDReportResult<Data>
  ) async -> PhysicalHIDReportResult<Data> {
    let admitted = outstanding.withLock { $0.insert(key).inserted }
    guard admitted else { return .failed(.ioReturn(kIOReturnBusy)) }
    return await withCheckedContinuation { continuation in
      let pending = Locked<CheckedContinuation<PhysicalHIDReportResult<Data>, Never>?>(
        continuation
      )
      @Sendable
      func finish(_ result: PhysicalHIDReportResult<Data>) {
        let waiting = pending.withLock {
          current -> CheckedContinuation<
            PhysicalHIDReportResult<Data>, Never
          >? in
          defer { current = nil }
          return current
        }
        waiting?.resume(returning: result)
      }
      DispatchQueue(label: "OpenJoystickDriver.HIDFeatureProbe").async { [outstanding] in
        let result = read()
        _ = outstanding.withLock { $0.remove(key) }
        finish(result)
      }
      scheduleDeadline(timeout) { finish(.failed(.ioReturn(kIOReturnTimeout))) }
    }
  }
}
