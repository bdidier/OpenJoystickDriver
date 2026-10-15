import Foundation
import IOKit

/// Runs a synchronous HID read off the caller's actor and gives up after a deadline, so a device
/// that never answers cannot hold up the caller. `IOHIDDeviceGetReport` has no timeout of its
/// own, and the read it started keeps its own queue until the system call returns.
enum BoundedHIDRead {
  /// The outcome of `read`, or a `kIOReturnTimeout` failure when it has not returned within
  /// `timeout` seconds.
  static func run(
    timeout: TimeInterval,
    read: @escaping @Sendable () -> PhysicalHIDReportResult<Data>
  ) async -> PhysicalHIDReportResult<Data> {
    await withCheckedContinuation { continuation in
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
      DispatchQueue(label: "OpenJoystickDriver.HIDFeatureProbe").async { finish(read()) }
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        finish(.failed(.ioReturn(kIOReturnTimeout)))
      }
    }
  }
}
