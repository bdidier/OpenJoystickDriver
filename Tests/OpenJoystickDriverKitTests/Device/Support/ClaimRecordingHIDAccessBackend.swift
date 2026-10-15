import Foundation

@testable import OpenJoystickDriverKit

actor ClaimRecordingHIDAccessBackend: HIDAccessBackend {
  private var released: [UInt32] = []
  private var reacquired: [UInt32] = []
  private var retried: [UInt32] = []
  private var elementValueRoutes: [UInt32] = []

  func releasedLocations() -> [UInt32] { released }
  func elementValueLocations() -> [UInt32] { elementValueRoutes }
  func reacquiredLocations() -> [UInt32] { reacquired }
  func retriedLocations() -> [UInt32] { retried }

  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { _ in } }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { [] }

  func setOutputReport(
    address _: ControllerConnectionAddress,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setOutputReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    address _: ControllerConnectionAddress,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func getFeatureReport(
    address _: ControllerConnectionAddress,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func getFeatureReport(
    connection _: HIDDeviceConnection,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func releaseInputClaim(address: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    released.append(contentsOf: [address.locationID].compactMap { $0 })
    return .released
  }

  func reacquireInputClaim(address: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    reacquired.append(contentsOf: [address.locationID].compactMap { $0 })
    return .reacquired
  }

  func retryInputClaim(address: ControllerConnectionAddress) {
    retried.append(contentsOf: [address.locationID].compactMap { $0 })
  }

  func routeElementValues(connection: HIDDeviceConnection) {
    elementValueRoutes.append(contentsOf: [connection.routingAddress.locationID].compactMap { $0 })
  }
}
