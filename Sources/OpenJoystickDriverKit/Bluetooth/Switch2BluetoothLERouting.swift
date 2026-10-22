import Foundation

/// Serves IOHID devices and Switch 2 Bluetooth LE controllers as one HID backend, routing each call
/// by the address of its connection.
final class BluetoothLECompositeHIDBackend: HIDAccessBackend {
  private let primary: any HIDAccessBackend
  private let hub: Switch2BluetoothLEHub

  init(primary: any HIDAccessBackend, hub: Switch2BluetoothLEHub) {
    self.primary = primary
    self.hub = hub
  }

  /// Merges both event streams. The merged stream ends when the IOHID stream ends, so an IOHID
  /// access failure still ends detection.
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    let primaryEvents = await primary.deviceEvents()
    let hubEvents = hub.events()
    let (merged, continuation) = AsyncStream.makeStream(of: HIDDeviceEvent.self)
    let primaryTask = Task {
      for await event in primaryEvents { continuation.yield(event) }
      continuation.finish()
    }
    let hubTask = Task { for await event in hubEvents { continuation.yield(event) } }
    continuation.onTermination = { _ in
      primaryTask.cancel()
      hubTask.cancel()
    }
    return merged
  }

  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    guard let primarySnapshots = await primary.currentConnectionSnapshots() else { return nil }
    return primarySnapshots + hub.connectionSnapshots()
  }

  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(address), case .gattPeripheral(let peripheralID) = address else {
      return await primary.setOutputReport(address: address, report: report)
    }
    return hub.setOutputReport(peripheralID: peripheralID, report: report)
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(connection.routingAddress),
      case .gattPeripheral(let peripheralID) = connection.routingAddress
    else {
      return await primary.setOutputReport(connection: connection, report: report)
    }
    return hub.setOutputReport(peripheralID: peripheralID, report: report)
  }

  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(address) else {
      return await primary.setFeatureReport(address: address, report: report)
    }
    return .unavailable
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(connection.routingAddress) else {
      return await primary.setFeatureReport(connection: connection, report: report)
    }
    return .unavailable
  }

  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    guard hub.owns(address) else {
      return await primary.getFeatureReport(address: address, request: request)
    }
    return .unavailable
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    guard hub.owns(connection.routingAddress) else {
      return await primary.getFeatureReport(connection: connection, request: request)
    }
    return .unavailable
  }

  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    guard hub.owns(connection.routingAddress) else {
      return await primary.probeFeatureReport(connection: connection, request: request)
    }
    return .unavailable
  }

  // macOS has no HID client for a GATT link, so OJD always owns its input.
  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard hub.owns(address) else {
      return await primary.releaseInputClaim(address: address)
    }
    return .released
  }

  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard hub.owns(address) else {
      return await primary.reacquireInputClaim(address: address)
    }
    return .reacquired
  }

  func retryInputClaim(address: ControllerConnectionAddress) async {
    guard !hub.owns(address) else { return }
    await primary.retryInputClaim(address: address)
  }

  func routeElementValues(connection: HIDDeviceConnection) async {
    guard !hub.owns(connection.routingAddress) else { return }
    await primary.routeElementValues(connection: connection)
  }

  /// Switch 2 Bluetooth LE controllers are never native gamepads, so only IOHID devices change.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    await primary.reevaluateOwnership(of: models)
  }
}

/// Opens a Switch 2 Bluetooth LE controller's command channel over GATT, and every other device
/// through the USB provider.
final class BluetoothLECompositeUSBTransportProvider: USBTransportProvider {
  private let base: (any USBTransportProvider)?
  private let hub: Switch2BluetoothLEHub

  init(base: (any USBTransportProvider)?, hub: Switch2BluetoothLEHub) {
    self.base = base
    self.hub = hub
  }

  func devices() async throws -> [USBTransportDevice] { try await base?.devices() ?? [] }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard let base else { throw USBTransportError.notFound }
    return try await base.open(device, options: options)
  }

  func openCommandChannel(
    at address: ControllerConnectionAddress,
    model: ControllerModelID,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    if case .gattPeripheral(let peripheralID) = address, hub.owns(address) {
      return Switch2BluetoothLECommandSession(hub: hub, peripheralID: peripheralID)
    }
    guard let base else { throw USBTransportError.notFound }
    return try await base.openCommandChannel(at: address, model: model, options: options)
  }

  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    guard let base else { return USBTransportResolution(profile: configured) }
    return await base.resolveTransport(for: device, configured: configured)
  }

  func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    await base?.physicalDeviceObservation(for: device)
  }

  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) async throws -> PhysicalDevice? {
    guard let base else { throw USBTransportError.notSupported }
    return try await base.configurationObservation(
      for: device,
      configurationValue: configurationValue
    )
  }

  func resetDevice(_ device: USBTransportDevice) async throws {
    guard let base else { throw USBTransportError.notSupported }
    try await base.resetDevice(device)
  }

  func exclusiveOwner(of device: USBTransportDevice) async throws -> String? {
    guard let base else { throw USBTransportError.notSupported }
    return try await base.exclusiveOwner(of: device)
  }
}

/// A Switch 2 command channel over GATT: OUT writes go to the command characteristic, and IN reads
/// return command-reply notifications.
final class Switch2BluetoothLECommandSession: USBTransportSession {
  private let hub: Switch2BluetoothLEHub
  private let peripheralID: UUID

  init(hub: Switch2BluetoothLEHub, peripheralID: UUID) {
    self.hub = hub
    self.peripheralID = peripheralID
  }

  var inputOwnership: HIDInputOwnership { .exclusive }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    guard USBEndpointDirection(endpointAddress: endpoint) == .out else {
      throw USBTransportError.notSupported
    }
    try hub.writeCommand(peripheralID: peripheralID, bytes: data)
    return data.count
  }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard USBEndpointDirection(endpointAddress: endpoint) == .in, length > 0 else {
      throw USBTransportError.notSupported
    }
    return try await hub.readReply(
      peripheralID: peripheralID,
      length: length,
      timeoutMilliseconds: timeout
    )
  }

  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }
}
