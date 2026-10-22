import Foundation
import IOKit
import OpenJoystickDriverKit

/// Waits for one IOKit interest notification that ends an exclusive hold on an interface.
///
/// `kIOMessageServiceWasClosed` is sent when a client closes the service and
/// `kIOMessageServiceIsTerminated` when the service goes away (`IOMessage.h`; both are
/// function-like macros that Swift does not import). Any other message ends the wait only once the
/// interface no longer names an owner.
final class InterfaceReleaseWatch: @unchecked Sendable {
  private static let wasClosed: UInt32 = 0xE000_0110
  private static let isTerminated: UInt32 = 0xE000_0010

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var finished = false
  private var port: IONotificationPortRef?
  private var notification: io_object_t = 0
  private let queue = DispatchQueue(label: "com.openjoystickdriver.iousbhost.release")
  private var service: io_service_t = 0

  func start(service: io_service_t) throws {
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
      throw USBTransportError.platform(code: 0, message: "IONotificationPortCreate failed")
    }
    self.port = port
    IONotificationPortSetDispatchQueue(port, queue)
    IOObjectRetain(service)
    self.service = service
    let result = IOServiceAddInterestNotification(
      port,
      service,
      kIOGeneralInterest,
      { refcon, _, messageType, _ in
        guard let refcon else { return }
        Unmanaged<InterfaceReleaseWatch>.fromOpaque(refcon).takeUnretainedValue()
          .received(messageType)
      },
      Unmanaged.passUnretained(self).toOpaque(),
      &notification
    )
    guard result == kIOReturnSuccess else {
      stop()
      throw IOUSBHostTransportProvider.transportError(result)
    }
    // The owner may have let go between the failed open and the registration.
    if !hasOwnerKey(service) { finish() }
  }

  func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      if finished {
        lock.unlock()
        continuation.resume()
      } else {
        self.continuation = continuation
        lock.unlock()
      }
    }
  }

  func finish() {
    lock.lock()
    finished = true
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume()
  }

  func stop() {
    if notification != 0 {
      IOObjectRelease(notification)
      notification = 0
    }
    if let port {
      IONotificationPortDestroy(port)
      self.port = nil
    }
    if service != 0 {
      IOObjectRelease(service)
      service = 0
    }
  }

  private func received(_ messageType: UInt32) {
    if messageType == Self.wasClosed || messageType == Self.isTerminated || !hasOwnerKey(service) {
      finish()
    }
  }

  private func hasOwnerKey(_ service: io_service_t) -> Bool {
    IORegistryEntryCreateCFProperty(
      service,
      IOUSBHostTransportProvider.exclusiveOwnerKey as CFString,
      kCFAllocatorDefault,
      0
    ) != nil
  }
}
