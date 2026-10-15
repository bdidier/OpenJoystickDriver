import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerServerFeedbackTests {
  private static func device(
    recordServer: ControllerServer = .system
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x2DC8,
      productID: 0x301B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .systemGamepad,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: recordServer,
      sessionToken: .fixture("device-feedback")
    )
  }

  private static func status(
    _ devices: [ApplicationServiceDeviceDescription]
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputRead: "granted",
      inputInject: "granted",
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
  }

  private static func shownServer(_ viewModel: RuntimeViewModel) -> ControllerServer? {
    guard case .available(let status) = viewModel.statusState else { return nil }
    return status.devices.first?.recordServer
  }

  @Test
  func anAcceptedToggleRefreshesUntilTheStatusCarriesTheNewOwnership() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    let toggle = Task { await viewModel.setControllerServer(.ojd, for: Self.device()) }
    await gateway.waitForStatusCall(count: 3)
    await gateway.setStatusPayload(Self.status([Self.device(recordServer: .ojd)]))
    await toggle.value

    #expect(Self.shownServer(viewModel) == .ojd)
    #expect(await gateway.statusCallCount <= 4)
  }

  @Test
  func anAcceptedToggleStopsRefreshingAfterTwoSeconds() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerServer(.ojd, for: Self.device())

    #expect(Self.shownServer(viewModel) == .system)
    #expect(await gateway.statusCallCount == 11)
  }

  @Test
  func aRefusedToggleRefreshesOnce() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setServerFailure(.noRecord)
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerServer(.ojd, for: Self.device())

    #expect(await gateway.statusCallCount == 1)
  }

  @Test(
    arguments: [
      (ControllerServerFailure.rawUSB, String?.none, OJDLocalized.string("error.E2023")),
      (.notNative, nil, OJDLocalized.string("error.E2023")),
      (.noRecord, nil, OJDLocalized.string("controllers.server.noRecord")),
      (
        .invalidRecord, "bad record",
        OJDLocalized.string("controllers.server.invalidRecord") + " bad record"
      ),
      (
        .persistenceFailed, "disk full",
        OJDLocalized.string("controllers.server.persistenceFailed") + " disk full"
      ),
    ]
  )
  func eachRefusalShowsItsOwnText(
    failure: ControllerServerFailure,
    detail: String?,
    expected: String
  ) async {
    let gateway = GatewayStub()
    await gateway.setServerFailure(failure, detail: detail)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setControllerServer(.ojd, for: device)

    let message = viewModel.controllerActionFailures[device.sessionToken.rawValue]
    #expect(message == expected)
  }

  @Test(
    arguments: [
      ("controllers.server.noRecord", OJDLocalized.string("controllers.server.noRecord")),
      (
        "controllers.server.invalidRecord",
        OJDLocalized.string("controllers.server.invalidRecord")
      ),
      (
        "controllers.server.persistenceFailed",
        OJDLocalized.string("controllers.server.persistenceFailed")
      ),
    ]
  )
  func eachNewTextIsLocalized(key: String, text: String) {
    #expect(text != key)
  }
}
