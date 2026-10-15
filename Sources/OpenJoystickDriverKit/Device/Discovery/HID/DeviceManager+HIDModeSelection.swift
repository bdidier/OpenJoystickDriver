import Foundation

/// Reads a probe's feature report from one HID connection. It can only read.
struct HIDConnectionModeProbeReader: ControllerModeProbeReader {
  let hidManager: HIDManager
  let connection: HIDDeviceConnection

  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await hidManager.getFeatureReport(connection: connection, request: request)
  }
}

extension DeviceManager {
  /// The mode a connected model's probes select. A record without modes costs no read.
  func selectedHIDMode(
    for connection: HIDDeviceConnection,
    vendorID: UInt16,
    productID: UInt16
  ) async -> ControllerModeSelection {
    await protocolDriverRegistry.selectMode(
      of: ControllerModelID(vendorID: vendorID, productID: productID),
      backend: connection.accessBackend,
      reader: HIDConnectionModeProbeReader(hidManager: hidManager, connection: connection)
    )
  }
}
