import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerOwnershipFeedbackTests {
  private static func device(
    recordOwnership: ControllerOwnership = .macOS
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x2DC8,
      productID: 0x301B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .nativeGamepad,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordOwnership: recordOwnership,
      sessionToken: .fixture("device-feedback")
    )
  }

  private static func status(
    _ devices: [ApplicationServiceDeviceDescription]
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
  }

  private static func shownOwnership(_ viewModel: RuntimeViewModel) -> ControllerOwnership? {
    guard case .available(let status) = viewModel.statusState else { return nil }
    return status.devices.first?.recordOwnership
  }

  @Test
  func anAcceptedToggleRefreshesUntilTheStatusCarriesTheNewOwnership() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    let toggle = Task { await viewModel.setControllerOwnership(.ojd, for: Self.device()) }
    await gateway.waitForStatusCall(count: 3)
    await gateway.setStatusPayload(Self.status([Self.device(recordOwnership: .ojd)]))
    await toggle.value

    #expect(Self.shownOwnership(viewModel) == .ojd)
    #expect(await gateway.statusCallCount <= 4)
  }

  @Test
  func anAcceptedToggleStopsRefreshingAfterTwoSeconds() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerOwnership(.ojd, for: Self.device())

    #expect(Self.shownOwnership(viewModel) == .macOS)
    #expect(await gateway.statusCallCount == 11)
  }

  @Test
  func aRefusedToggleRefreshesOnce() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setOwnershipFailure(.noRecord)
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerOwnership(.ojd, for: Self.device())

    #expect(await gateway.statusCallCount == 1)
  }

  @Test(
    arguments: [
      (ControllerOwnershipFailure.rawUSB, String?.none, OJDLocalized.string("error.E2023")),
      (.notNative, nil, OJDLocalized.string("error.E2023")),
      (.noRecord, nil, OJDLocalized.string("controllers.ownership.noRecord")),
      (
        .invalidRecord, "bad record",
        OJDLocalized.string("controllers.ownership.invalidRecord") + " bad record"
      ),
      (
        .persistenceFailed, "disk full",
        OJDLocalized.string("controllers.ownership.persistenceFailed") + " disk full"
      ),
    ]
  )
  func eachRefusalShowsItsOwnText(
    failure: ControllerOwnershipFailure,
    detail: String?,
    expected: String
  ) async {
    let gateway = GatewayStub()
    await gateway.setOwnershipFailure(failure, detail: detail)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setControllerOwnership(.ojd, for: device)

    let message = viewModel.controllerActionFailures[device.sessionToken.rawValue]
    #expect(message == expected)
  }

  @Test(
    arguments: [
      ("controllers.ownership.noRecord", OJDLocalized.string("controllers.ownership.noRecord")),
      (
        "controllers.ownership.invalidRecord",
        OJDLocalized.string("controllers.ownership.invalidRecord")
      ),
      (
        "controllers.ownership.persistenceFailed",
        OJDLocalized.string("controllers.ownership.persistenceFailed")
      ),
    ]
  )
  func eachNewTextIsLocalized(key: String, text: String) {
    #expect(text != key)
  }
}
