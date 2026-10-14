import SwifterKit
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverUSB

/// Issue #18: pins how `045E:02D1` (Xbox One model 1537) reaches raw USB detection.
struct XboxOne02D1DetectionTests {
  private static let vendorID: UInt16 = 0x045E
  private static let productID: UInt16 = 0x02D1

  @Test
  func dextRouteServiceIsClaimedOnInterfaceZero() async {
    let device = USBTransportDevice(
      route: .usbDriverKit,
      serviceID: 40,
      vendorID: Self.vendorID,
      productID: Self.productID,
      locationID: 40
    )
    let provider = USBDiscoveryRecordingProvider(devices: [device])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider
    )

    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed([
          DeviceIdentifier(
            vendorID: Self.vendorID,
            productID: Self.productID,
            locationID: 40,
            interfaceNumber: 0
          )
        ])
    )
    await manager.stop()
  }

  @Test
  func extensionMatchesTheModel() {
    #expect(USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(Self.productID))
  }

  /// The generated personality lists seven products, so SwifterKit writes `idProductArray` and no
  /// scalar `idProduct`. The DEXT service carries its personality, so the adapter drops it. This
  /// pins the defect recorded in `docs/testing/xbox-one-02d1.md`; change it with the fix.
  @Test
  func dextServiceWithPersonalityPropertiesYieldsNoDevice() {
    let service = DriverService(
      id: 41,
      name: "SwifterKitRuntimeService",
      properties: [
        "idVendor": .unsignedInteger(UInt64(Self.vendorID)),
        "idProductArray": .array(
          USBDriverKitExtensionConfiguration.microsoftProductIDs.map {
            .unsignedInteger(UInt64($0))
          }
        ),
        "bInterfaceNumber": .unsignedInteger(0),
      ]
    )
    #expect(USBDriverKitTransportProvider.device(service) == nil)
  }

  @Test
  func facadeKeepsTheModelOffDirectIOUSBHostWithoutADextService() {
    let direct = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 42,
      vendorID: Self.vendorID,
      productID: Self.productID,
      locationID: 42
    )
    let model = USBTransportModel(direct)
    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [],
        supportedRawUSBModels: [model],
        requiredDriverKitModels: [model]
      ).isEmpty
    )
  }
}
