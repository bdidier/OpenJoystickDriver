import Foundation
import IOKit

/// HID discovery reports no endpoint set. The registry publishes only `bNumEndpoints` on the
/// `IOUSBHostInterface`: it has no `IOUSBHostPipe` children and no endpoint or configuration
/// descriptor properties (checked with `ioreg` on macOS 27 and in `IOUSBHostFamilyDefinitions.h`),
/// so an `endpoints` key selects a mode only on the raw USB scanner, which reads descriptors.
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
}
