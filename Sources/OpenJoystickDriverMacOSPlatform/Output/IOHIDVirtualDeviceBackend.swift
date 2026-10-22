import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

struct IOKitReportError: Error, Sendable { let code: IOReturn }

/// One `IOHIDUserDevice`: created unpublished, then published by ``activate(hostReports:)``.
final class IOHIDVirtualDeviceBackend: VirtualDeviceBackend, @unchecked Sendable {
  private var device: IOHIDUserDevice?
  private let queue: DispatchQueue
  private let lock = NSLock()
  private var isClosed = false
  /// Serial queue for blocking report calls; the sender's single worker already orders them.
  private let sendQueue = DispatchQueue(label: "com.openjoystickdriver.output.report")

  /// Longest wait for the cancel handler before teardown is reported as finished anyway.
  static let cancellationTimeoutNanoseconds: UInt64 = 2_000_000_000
  private let cancellation = Locked(Cancellation())

  private struct Cancellation {
    var completed = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  init(device: IOHIDUserDevice, queue: DispatchQueue) {
    self.device = device
    self.queue = queue
    // The cancel handler must be set before activation. It retains the device, as
    // IOHIDUserDevice.h requires, until the cancel has been fully delivered.
    IOHIDUserDeviceSetCancelHandler(device) { [weak self, device] in
      _ = device
      self?.finishCancellation()
    }
  }

  deinit { close() }

  func activate(hostReports: UserSpaceHostReportHandler) {
    guard let device = lock.withLock({ isClosed ? nil : device }) else { return }
    IOHIDUserDeviceRegisterGetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard let identifier = UInt32(exactly: reportID) else {
          throw VirtualHostReportError.malformed
        }
        let bytes = try hostReports.getReport(
          type: try Self.reportType(type),
          reportID: identifier,
          maxSize: Int(reportLength.pointee)
        )
        for (index, byte) in bytes.enumerated() { report[index] = byte }
        reportLength.pointee = bytes.count
        return kIOReturnSuccess
      } catch {
        reportLength.pointee = 0
        return Self.ioKitError(error)
      }
    }
    IOHIDUserDeviceRegisterSetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard reportLength >= 0 else { throw VirtualHostReportError.malformed }
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
        try hostReports.acknowledgeSetReport(
          type: try Self.reportType(type),
          reportID: reportID,
          bytes: bytes
        )
        return kIOReturnSuccess
      } catch { return Self.ioKitError(error) }
    }
    IOHIDUserDeviceSetDispatchQueue(device, queue)
    IOHIDUserDeviceActivate(device)
  }

  private func finishCancellation() {
    let waiters = cancellation.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.completed = true
      defer { state.waiters.removeAll() }
      return state.waiters
    }
    waiters.forEach { $0.resume() }
  }

  /// Suspends until the device's cancel handler ran, so the device no longer publishes.
  func waitUntilClosed() async {
    // A device that never reports cancellation must not stall teardown forever. The limit runs
    // on a timer thread, so a starved cooperative pool cannot extend it.
    let cancelTimeout = DeadlineTimer.dispatch.schedule(Self.cancellationTimeoutNanoseconds) {
      [weak self] in self?.finishCancellation()
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let done = cancellation.withLock { state -> Bool in
        if state.completed { return true }
        state.waiters.append(continuation)
        return false
      }
      if done { continuation.resume() }
    }
    cancelTimeout()
  }

  /// Runs the blocking native report call off the cooperative pool.
  func send(_ report: [UInt8]) async throws {
    try await BlockingWork.run(on: sendQueue) { [self] in try sendNow(report) }
  }

  private func sendNow(_ report: [UInt8]) throws {
    guard let device = lock.withLock({ isClosed ? nil : device }) else {
      throw CancellationError()
    }
    // Interrupt IN for IOKit clients (`hid_read`). GetReport is a separate control path.
    let result = report.withUnsafeBytes { pointer -> IOReturn in
      guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
      return IOHIDUserDeviceHandleReportWithTimeStamp(
        device,
        mach_absolute_time(),
        base.assumingMemoryBound(to: UInt8.self),
        pointer.count
      )
    }
    guard result == kIOReturnSuccess else { throw IOKitReportError(code: result) }
  }

  func close() {
    let device = lock.withLock { () -> IOHIDUserDevice? in
      guard !isClosed else { return nil }
      isClosed = true
      defer { self.device = nil }
      return self.device
    }
    if let device { IOHIDUserDeviceCancel(device) }
  }

  static func reportType(_ type: IOHIDReportType) throws -> VirtualHostReportType {
    switch type {
    case kIOHIDReportTypeInput: .input
    case kIOHIDReportTypeOutput: .output
    case kIOHIDReportTypeFeature: .feature
    default: throw VirtualHostReportError.unsupported
    }
  }

  static func ioKitError(_ error: any Error) -> IOReturn {
    switch error {
    case VirtualHostReportError.unsupported: kIOReturnUnsupported
    case VirtualHostReportError.malformed: kIOReturnBadArgument
    case VirtualHostReportError.tooLarge: kIOReturnMessageTooLarge
    case VirtualHostReportError.closed: kIOReturnNotOpen
    case is CancellationError: kIOReturnAborted
    default: kIOReturnError
    }
  }
}
