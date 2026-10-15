import Foundation

@testable import OpenJoystickDriverKit

actor RecoveryHIDBackend: HIDAccessBackend {
  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { $0.finish() } }

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

  func releaseInputClaim(address _: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    .unavailable
  }

  func reacquireInputClaim(address _: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    .unavailable
  }

  func retryInputClaim(address _: ControllerConnectionAddress) {}

  func routeElementValues(connection _: HIDDeviceConnection) {}
}
