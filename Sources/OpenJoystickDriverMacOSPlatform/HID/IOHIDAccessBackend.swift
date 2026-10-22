import Foundation
import OpenJoystickDriverKit

private final class IOHIDAccessBackend: HIDAccessBackend, Sendable {
  private let stream: HIDDeviceStream

  init(
    additionalProfileModels: @escaping @Sendable () -> [ControllerModelID],
    roleProfileModels: @escaping @Sendable () -> [ControllerModelID]
  ) {
    stream = HIDDeviceStream(
      additionalProfileModels: additionalProfileModels,
      roleProfileModels: roleProfileModels
    )
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    await MainActor.run { stream.deviceEvents() }
  }

  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await stream.currentConnectionSnapshots()
  }

  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard let locationID = address.locationID else { return .unavailable }
    return stream.setOutputReport(locationID: locationID, report: report)
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await stream.setOutputReport(connection: connection, report: report)
  }

  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard let locationID = address.locationID else { return .unavailable }
    return stream.setFeatureReport(locationID: locationID, report: report)
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await stream.setFeatureReport(connection: connection, report: report)
  }

  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    guard let locationID = address.locationID else { return .unavailable }
    return stream.getFeatureReport(locationID: locationID, request: request)
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await stream.getFeatureReport(connection: connection, request: request)
  }

  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await stream.probeFeatureReport(connection: connection, request: request)
  }

  // Seizes and closes run on main, where the manager's run loop removes devices: a device that
  // detaches mid-open must not lose its plug-in on another thread, and `retryInputClaim` yields to
  // the main-confined stream continuation.
  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard let locationID = address.locationID else { return .unavailable }
    return await MainActor.run { stream.releaseInputClaim(locationID: locationID) }
  }

  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard let locationID = address.locationID else { return .unavailable }
    return await MainActor.run { stream.reacquireInputClaim(locationID: locationID) }
  }

  func retryInputClaim(address: ControllerConnectionAddress) async {
    guard let locationID = address.locationID else { return }
    await MainActor.run { stream.retryInputClaim(locationID: locationID) }
  }

  func routeElementValues(connection: HIDDeviceConnection) async {
    await stream.routeElementValues(connection: connection)
  }

  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    await MainActor.run { stream.reevaluateOwnership(of: models) }
  }
}

/// The IOHID-backed HID access of the application.
package func makeIOHIDAccessBackend(
  additionalProfileModels: @escaping @Sendable () -> [ControllerModelID],
  roleProfileModels: @escaping @Sendable () -> [ControllerModelID]
) -> any HIDAccessBackend {
  IOHIDAccessBackend(
    additionalProfileModels: additionalProfileModels,
    roleProfileModels: roleProfileModels
  )
}
