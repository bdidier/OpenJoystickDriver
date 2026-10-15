import Foundation
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct VirtualControllerBackendTests {
  @Test
  func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.publishesConsumerGamepad)
    #expect(VirtualControllerBackendID.allCases.contains(.gameControllerHID))
    #expect(!capabilities.notes.isEmpty)
  }

  @Test
  func testUserSpaceSerialUsesStableHashedPhysicalIdentity() {
    let identifier = LogicalControllerID(
      vendorID: 13623,
      productID: 4112,
      serialNumber: "physical-serial"
    )
    let serial = UserSpaceVirtualDeviceConstants.serialNumber(for: identifier)

    #expect(serial.hasPrefix(UserSpaceVirtualDeviceConstants.serialPrefix))
    #expect(serial.count == UserSpaceVirtualDeviceConstants.serialPrefix.count + 16)
    #expect(serial.suffix(16).allSatisfy { $0.isHexDigit })
    #expect(serial == UserSpaceVirtualDeviceConstants.serialNumber(for: identifier))
  }

  @Test
  func nonStandardButtonsKeepDistinctNormalizedBits() {
    func bit(_ control: Control) -> UInt32? {
      UserSpaceOutputDispatcher.buttonBit(for: control)
    }

    #expect(bit(.capture) == 15)
    #expect(bit(.back) == 9)
    #expect(bit(.start) == 8)
    #expect(bit(.rightTrackpadClick) == 7)
    #expect(bit(.microphone) == nil)
    #expect(bit(.touchpadClick) == nil)
  }

  @Test
  func testUserSpaceXboxOneSIdentityAdvertisesNumberedReportSizes() throws {
    let format = try XboxGeckoHIDReportFormat()
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .sdlCompatible,
      format: format,
      identifier: LogicalControllerID(vendorID: 13623, productID: 4112)
    )

    let inputSize = properties[kIOHIDMaxInputReportSizeKey as String] as? Int
    let outputSize = properties[kIOHIDMaxOutputReportSizeKey as String] as? Int
    #expect(inputSize == format.inputReportPayloadSize + 1)
    #expect(outputSize == ConsumerOutputCodec.xboxOneReportPayloadSize + 1)
  }

  @Test
  func testIOKitPropertiesPreserveDescriptorAndIdentity() throws {
    let format = try XboxGeckoHIDReportFormat()
    let profile = VirtualDeviceProfile.sdlCompatible
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile,
      format: format,
      identifier: LogicalControllerID(vendorID: 13623, productID: 4112)
    )

    #expect(properties[kIOHIDReportDescriptorKey as String] as? Data == Data(format.descriptor))
    #expect(properties[kIOHIDVendorIDKey as String] as? Int == Int(profile.vendorID))
    #expect(properties[kIOHIDProductIDKey as String] as? Int == Int(profile.productID))
    #expect(properties[kIOHIDVersionNumberKey as String] as? Int == profile.versionNumber)
    #expect(profile.versionNumber == 0)
  }

  @Test
  func testUserSpaceDispatcherFailsFastWithoutVirtualDeviceEntitlement() throws {
    guard !UserSpaceOutputDispatcher.hasRequiredVirtualDeviceEntitlement else { return }

    do {
      _ = try UserSpaceOutputDispatcher(
        profile: .generic,
        format: OJDGenericGamepadFormat()
      )
      Issue.record("UserSpaceOutputDispatcher should require the virtual HID entitlement")
    } catch UserSpaceOutputDispatcher.CreationError.missingEntitlement(let entitlement) {
      #expect(entitlement == UserSpaceOutputDispatcher.requiredVirtualDeviceEntitlement)
    } catch { Issue.record("Unexpected error: \(error)") }
  }

  @Test
  func testXboxOneVirtualOutputFormatDeclaresRumbleOutputSize() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.oneSDescriptor,
      outputReportID: ConsumerOutputCodec.xboxOneReportID,
      outputReportPayloadSize: ConsumerOutputCodec.xboxOneReportPayloadSize
    )

    #expect(format.inputReportID == 1)
    #expect(format.outputReportID == ConsumerOutputCodec.xboxOneReportID)
    #expect(format.outputReportPayloadSize == ConsumerOutputCodec.xboxOneReportPayloadSize)
  }

  @Test
  func testVirtualOutputFormatsReturnFullyNeutralReportsAfterRelease() throws {
    let generic = OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let xone = try XboxGeckoHIDReportFormat().buildInputReport(from: VirtualGamepadState())

    #expect(generic == [UInt8](repeating: 0, count: generic.count))
    #expect(xone[0] == 1)
    #expect(Array(xone[1...8]) == [0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80])
    #expect(xone[14] == 0x00)
    #expect(xone[15] == 0x00)
    #expect(xone.count == 16)
  }

  @Test
  func userSpaceCreationErrorsDistinguishPermissionFromEntitlementAndCreation() {
    let errors: [UserSpaceOutputDispatcher.CreationError] = [
      .inputMonitoringDenied, .accessibilityDenied, .createFailed, .missingEntitlement("test"),
    ]
    for error in errors {
      switch error {
      case .inputMonitoringDenied, .accessibilityDenied, .createFailed, .missingEntitlement: break
      }
    }
  }
}
