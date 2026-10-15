import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerOwnershipPickerTests {
  private static func device(
    physicalOwnership: ControllerOwnershipObservation = .exclusiveHID,
    recordServer: ControllerServer = .system,
    discoverySource: DeviceDiscoverySource = .hid
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x3537,
      productID: 0x100B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: discoverySource,
      physicalOwnership: physicalOwnership,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: recordServer,
      sessionToken: .fixture("device-ownership")
    )
  }

  @Test(
    arguments: [
      (
        ControllerOwnershipObservation.nativeGamepad, ControllerServer.system,
        DeviceDiscoverySource.hid, true
      ),
      (.exclusiveHID, .ojd, .hid, true),
      (.nativeGamepad, .ojd, .hid, true),
      (.exclusiveHID, .system, .hid, false),
      (.nativeHIDVisible, .system, .hid, false),
      (.nativeGamepad, .system, .rawUSB, false),
      (.exclusiveRawUSB, .ojd, .rawUSB, false),
    ]
  )
  func thePickerShowsOnlyForANativeOrOJDOwnedHIDController(
    physicalOwnership: ControllerOwnershipObservation,
    recordServer: ControllerServer,
    discoverySource: DeviceDiscoverySource,
    shown: Bool
  ) {
    let device = Self.device(
      physicalOwnership: physicalOwnership,
      recordServer: recordServer,
      discoverySource: discoverySource
    )

    #expect(ControllerOwnershipPicker.isShown(for: device) == shown)
  }

  @Test(arguments: [ControllerServer.ojd, .system])
  func aChangeCallsTheGatewayWithTheModelIdentityAndTheValue(_ ownership: ControllerServer) async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(physicalOwnership: .nativeGamepad)

    await viewModel.setControllerOwnership(ownership, for: device)

    let requests = await gateway.ownershipRequests
    #expect(requests.count == 1)
    #expect(requests.first?.model == ControllerModelID(vendorID: 0x3537, productID: 0x100B))
    #expect(requests.first?.ownership == ownership)
    #expect(viewModel.controllerActionFailures[device.sessionToken.rawValue] == nil)
  }

  @Test
  func aRefusalShowsE2023WithTheServiceDetail() async {
    let gateway = GatewayStub()
    await gateway.setOwnershipFailure(.invalidRecord, detail: "bad record")
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(physicalOwnership: .nativeGamepad)

    await viewModel.setControllerOwnership(.ojd, for: device)

    let message = viewModel.controllerActionFailures[device.sessionToken.rawValue]
    #expect(message == OJDLocalized.string("controllers.ownership.invalidRecord") + " bad record")
  }
}
