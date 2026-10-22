import Foundation

/// Why a physical HID request or access stream failed, as the platform backend reports it.
public enum PhysicalHIDFailure: Sendable, Equatable, CustomStringConvertible {
  /// A bounded read gave up at its deadline.
  case timedOut
  /// An earlier bounded read of the same device is still outstanding.
  case busy
  /// The device or its link did not respond to a write.
  case notResponding
  /// The device itself declined the request: a stalled control pipe or an unsupported request.
  case declined
  /// A status code of the host's HID stack that has no name here.
  case hostStatus(Int32)

  public var description: String {
    switch self {
    case .timedOut: "timed out"
    case .busy: "busy"
    case .notResponding: "not responding"
    case .declined: "declined by the device"
    case .hostStatus(let code): "host status \(code)"
    }
  }
}

public enum PhysicalHIDReportResult<Value: Sendable>: Sendable {
  case success(Value)
  case unavailable
  case failed(PhysicalHIDFailure)
}

extension PhysicalHIDReportResult {
  var value: Value? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  var succeeded: Bool {
    if case .success = self { return true }
    return false
  }

  var failureDescription: String {
    switch self {
    case .success: "success"
    case .unavailable: "HID interface unavailable"
    case .failed(let failure): failure.description
    }
  }
}

public enum PhysicalHIDClaimResult: Sendable, Equatable {
  case released
  case reacquired
  case unavailable
  case failed(PhysicalHIDFailure)
}

/// A connection token and ownership observed by the active physical HID backend.
public struct HIDDeviceConnectionSnapshot: Equatable, Sendable {
  public let connection: HIDDeviceConnection
  public let ownership: HIDInputOwnership

  public init(connection: HIDDeviceConnection, ownership: HIDInputOwnership) {
    self.connection = connection
    self.ownership = ownership
  }

  package static func reconcile(
    trackedConnections: [UInt64: HIDDeviceConnection],
    presentDeviceIDs: Set<UInt64>,
    ownershipByLocation: [UInt32: HIDInputOwnership]
  ) -> [Self] {
    trackedConnections.compactMap { deviceID, connection in
      guard presentDeviceIDs.contains(deviceID) else { return nil }
      return Self(
        connection: connection,
        ownership: connection.routingAddress.locationID.flatMap { ownershipByLocation[$0] }
          ?? .unknown
      )
    }.sorted {
      let leftAddress = $0.connection.routingAddress
      let rightAddress = $1.connection.routingAddress
      if leftAddress != rightAddress { return leftAddress < rightAddress }
      return $0.connection.connectionID.uuidString < $1.connection.connectionID.uuidString
    }
  }
}

package protocol HIDAccessBackend: Sendable {
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent>
  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]?
  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  /// Reads a feature report for a mode probe, which must not wait on a silent device.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult
  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult
  /// Re-runs the seize of an address's devices whose earlier attempt was refused or failed.
  func retryInputClaim(address: ControllerConnectionAddress) async
  func routeElementValues(connection: HIDDeviceConnection) async
  /// Admits again each device of a model in `models` whose native pass-through changed with
  /// the current records, and returns the connections it admitted.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID>
}

extension HIDAccessBackend {
  /// A backend with no bounded read reads as the startup reads do.
  package func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await getFeatureReport(connection: connection, request: request)
  }

  /// A backend whose devices never pass through to macOS has nothing to re-evaluate.
  package func reevaluateOwnership(of _: Set<ControllerModelID>) -> Set<UUID> { [] }
}

/// The physical HID access of the application over a platform backend.
///
/// The host supplies the backend; `bluetoothLEHub` adds the Switch 2 controllers connected over
/// Bluetooth LE GATT. Tests inject fake backends.
public final class HIDManager: Sendable {
  private let backend: any HIDAccessBackend

  package init(backend: any HIDAccessBackend) { self.backend = backend }

  /// Serves `primary`'s devices and the hub's Bluetooth LE controllers as one backend, or only
  /// `primary`'s devices without a hub.
  package init(primary: any HIDAccessBackend, bluetoothLEHub: Switch2BluetoothLEHub?) {
    backend =
      bluetoothLEHub.map { BluetoothLECompositeHIDBackend(primary: primary, hub: $0) } ?? primary
  }

  public func deviceEvents() async -> AsyncStream<HIDDeviceEvent> { await backend.deviceEvents() }

  /// Returns exact current connections, or `nil` if the backend cannot confirm presence.
  /// An empty array is a confirmed observation with no tracked current connections.
  public func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await backend.currentConnectionSnapshots()
  }

  public func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setOutputReport(address: address, report: report)
  }

  /// Sends a report only to the exact connection lifetime previously observed by the backend.
  /// Unlike route-based output, this never falls back to another device at the same location.
  public func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setOutputReport(connection: connection, report: report)
  }

  public func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setFeatureReport(address: address, report: report)
  }

  /// Sends a feature report only to the exact connection lifetime previously observed by the
  /// backend.
  public func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setFeatureReport(connection: connection, report: report)
  }

  public func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.getFeatureReport(address: address, request: request)
  }

  /// Reads a feature report only from the exact connection lifetime previously observed by the
  /// backend, never from a sibling interface at its location.
  public func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.getFeatureReport(connection: connection, request: request)
  }

  /// Reads a feature report for a mode probe. It gives up after a deadline, and while an
  /// earlier probe read of the connection is outstanding it fails at once.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.probeFeatureReport(connection: connection, request: request)
  }

  public func releaseInputClaim(
    address: ControllerConnectionAddress
  ) async -> PhysicalHIDClaimResult {
    await backend.releaseInputClaim(address: address)
  }

  public func reacquireInputClaim(
    address: ControllerConnectionAddress
  ) async -> PhysicalHIDClaimResult {
    await backend.reacquireInputClaim(address: address)
  }

  public func retryInputClaim(address: ControllerConnectionAddress) async {
    await backend.retryInputClaim(address: address)
  }

  /// Delivers a connection's decoded element values, for a driver that parses them.
  public func routeElementValues(connection: HIDDeviceConnection) async {
    await backend.routeElementValues(connection: connection)
  }

  /// Admits again each device of a model in `models` whose native pass-through changed with
  /// the current records, so a changed `ownership` seizes or releases it without a replug.
  /// Returns the connections it admitted; their `.connected` events are already queued.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    await backend.reevaluateOwnership(of: models)
  }
}
