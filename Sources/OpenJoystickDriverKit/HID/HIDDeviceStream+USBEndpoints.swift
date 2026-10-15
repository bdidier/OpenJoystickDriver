import Foundation
import IOKit

extension HIDDeviceStream {
  /// The retained `IOUSBHostInterface` a HID device is published on, found by walking the
  /// IORegistry service-plane parents. The caller releases it. Nil when there is none.
  static func retainedUSBInterfaceEntry(for device: IOHIDDevice) -> io_registry_entry_t? {
    var entry = IOHIDDeviceGetService(device)
    guard entry != 0, IOObjectRetain(entry) == KERN_SUCCESS else { return nil }
    while IOObjectConformsTo(entry, "IOUSBHostInterface") == 0 {
      var parent: io_registry_entry_t = 0
      let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
      IOObjectRelease(entry)
      guard result == KERN_SUCCESS else { return nil }
      entry = parent
    }
    return entry
  }

  /// The endpoint set of the USB interface a USB-hosted HID device is published on, or nil when
  /// it cannot be read completely. Bluetooth HID has no USB interface, so it reports no
  /// endpoints and never matches an `endpoints` key.
  static func usbEndpoints(
    for device: IOHIDDevice,
    hostTransport: PhysicalTransport?
  ) -> [PhysicalEndpointSignature]? {
    guard hostTransport == .usb, let entry = retainedUSBInterfaceEntry(for: device) else {
      return nil
    }
    defer { IOObjectRelease(entry) }
    let declared = registryProperties(of: entry)["bNumEndpoints"] as? Int
    var iterator: io_iterator_t = 0
    guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
      return nil
    }
    defer { IOObjectRelease(iterator) }
    var pipes: [[String: Any]] = []
    while case let child = IOIteratorNext(iterator), child != 0 {
      if IOObjectConformsTo(child, "IOUSBHostPipe") != 0 {
        pipes.append(registryProperties(of: child))
      }
      IOObjectRelease(child)
    }
    return endpoints(fromPipeProperties: pipes, declaredCount: declared)
  }

  private static func registryProperties(of entry: io_registry_entry_t) -> [String: Any] {
    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        == KERN_SUCCESS
    else { return [:] }
    return properties?.takeRetainedValue() as? [String: Any] ?? [:]
  }

  /// Maps the registry properties of an interface's pipes to endpoint signatures. Nil when a
  /// pipe lacks its address or attributes, when an address repeats, or when the pipe count is not
  /// the interface's declared `bNumEndpoints`: a partial set must not match an endpoint set.
  static func endpoints(
    fromPipeProperties pipes: [[String: Any]],
    declaredCount: Int?
  ) -> [PhysicalEndpointSignature]? {
    let endpoints = pipes.map(endpoint(fromPipeProperties:))
    guard let declaredCount, declaredCount == pipes.count,
      let complete = endpoints as? [PhysicalEndpointSignature]
    else { return nil }
    let addresses = complete.compactMap(\.address)
    return Set(addresses).count == addresses.count ? complete : nil
  }

  static func endpoint(fromPipeProperties properties: [String: Any]) -> PhysicalEndpointSignature? {
    guard let address = (properties["bEndpointAddress"] as? Int).flatMap(UInt8.init(exactly:)),
      let attributes = (properties["bmAttributes"] as? Int).flatMap(UInt8.init(exactly:))
    else { return nil }
    let transferType: USBEndpointTransferType =
      switch attributes & 0x03 {
      case 0: .control
      case 1: .isochronous
      case 2: .bulk
      default: .interrupt
      }
    return PhysicalEndpointSignature(
      address: address,
      direction: address & 0x80 == 0 ? .out : .in,
      transferType: transferType,
      maxPacketSize: (properties["wMaxPacketSize"] as? Int).flatMap(UInt16.init(exactly:)),
      interval: (properties["bInterval"] as? Int).flatMap(UInt8.init(exactly:))
    )
  }
}
