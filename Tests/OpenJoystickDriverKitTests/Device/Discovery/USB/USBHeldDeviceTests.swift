import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A raw-USB device whose configuration descriptor read is refused because another owner holds it
/// is acknowledged once, with a reason, and admitted again when its holder goes away.
struct USBHeldDeviceTests {
  private let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 0x3a32,
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 0x0113_0000
  )

  private func makeProvider(owner: String?) -> HeldDeviceProvider {
    HeldDeviceProvider(
      device: device,
      passive: PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        configurationValue: 1,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x47,
            interfaceProtocol: 0xD0,
            endpoints: nil
          )
        ]
      ),
      owner: owner
    )
  }

  private func makeManager(_ provider: HeldDeviceProvider) -> DeviceManager {
    DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
  }

  @Test
  func deniedDescriptorReadIsAcknowledgedAndReadOnce() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()

    for _ in 0..<3 {
      for event in enumeration.events(for: .available([device])) {
        guard case .attached(let attached) = event else { continue }
        let outcome = await manager.handleUSBDeviceAdded(attached, provider: provider)
        #expect(outcome == .ignored)
        if outcome == .ignored { enumeration.acknowledge(attached) }
      }
    }

    #expect(await provider.descriptorReads == [1])
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse])
    await manager.stop()
  }

  @Test
  func theDetectionLoopReadsAHeldDeviceOnceAcrossPolls() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    let detection = Task { await manager.runUSBDetection() }
    await waitUntil("the held device is recorded") {
      await manager.unboundDeviceDescriptions().count == 1
    }
    // Two more polls pass; the service stays acknowledged and is not read again.
    try? await Task.sleep(nanoseconds: 2 * usbDetectionPollNanoseconds + 200_000_000)
    #expect(await provider.descriptorReads == [1])
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.deviceInUse])
    detection.cancel()
    await detection.value
    await manager.stop()
  }

  @Test
  func onlyTheHeldReasonHasAnExplanationInTheCatalog() {
    let explained = ProtocolBindingReason.allCases.filter { $0.explanationKey != nil }
    #expect(explained == [.deviceInUse])
    let localization = Localization()
    for reason in explained {
      let key = reason.explanationKey ?? ""
      #expect(localization.string(key) != key)
    }
  }

  @Test
  func heldServiceIsAdmittedAgainOnlyWhenItsHolderGoesAway() async {
    let provider = makeProvider(owner: "pid 11070, steam_osx")
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    enumeration.acknowledge(device)

    await manager.releaseHeldUSBServices(in: &enumeration, provider: provider)
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)
    #expect(await manager.heldUSBServices.count == 1)

    await provider.setOwner(nil)
    await manager.releaseHeldUSBServices(in: &enumeration, provider: provider)
    #expect(enumeration.acknowledgedDevices.isEmpty)
    #expect(await manager.heldUSBServices.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func deniedReadWithoutARegistryOwnerStaysHeldUntilReenumeration() async {
    let provider = makeProvider(owner: nil)
    let manager = makeManager(provider)
    var enumeration = USBEnumerationTracker()
    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    enumeration.acknowledge(device)

    await manager.releaseHeldUSBServices(in: &enumeration, provider: provider)
    #expect(enumeration.acknowledgedDevices[device.serviceAddress] != nil)
    #expect(await provider.descriptorReads == [1])
    await manager.stop()
  }
}

actor HeldDeviceProvider: USBTransportProvider {
  let device: USBTransportDevice
  let passive: PhysicalDevice
  private var owner: String?
  private(set) var descriptorReads: [UInt8] = []

  init(device: USBTransportDevice, passive: PhysicalDevice, owner: String?) {
    self.device = device
    self.passive = passive
    self.owner = owner
  }

  func setOwner(_ owner: String?) { self.owner = owner }

  func devices() -> [USBTransportDevice] { [device] }

  func physicalDeviceObservation(for device: USBTransportDevice) -> PhysicalDevice? { passive }

  func resolveTransport(
    for device: USBTransportDevice,
    configured profile: DeviceTransportProfile
  ) -> USBTransportResolution { USBTransportResolution(profile: profile, physicalDevice: passive) }

  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    descriptorReads.append(configurationValue)
    throw USBTransportError.accessDenied
  }

  func exclusiveOwner(of device: USBTransportDevice) -> String? { owner }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession { throw USBTransportError.accessDenied }
}
