import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DiagnosticsServiceTests {
  @Test
  func aVirtualDeviceErrorShowsItsMessageOnce() {
    let status = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .error("Missing entitlement")
    )
    let check = DiagnosticsService.virtualDeviceCheck(
      DiagnoseServiceSnapshot(
        availability: .running,
        status: status,
        virtualDiagnostics: nil,
        frameTimings: nil
      )
    )

    #expect(
      check == DiagnoseCheck("virtual-device", .fail, "virtual gamepad error: Missing entitlement")
    )
  }
}
