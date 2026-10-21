import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileCreationFieldsTests {
  private static func device(
    _ name: String,
    token: String,
    vendorID: UInt16,
    productID: UInt16
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: vendorID,
      productID: productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      sessionToken: .fixture(token)
    )
  }

  private static let pads = [
    device("Pad A", token: "a", vendorID: 0x0001, productID: 0x0002),
    device("Pad B", token: "b", vendorID: 0x0003, productID: 0x0004),
  ]

  private static let tokenA = pads[0].sessionToken.rawValue
  private static let tokenB = pads[1].sessionToken.rawValue

  @Test
  func theFirstControllerIsChosenAndNamesTheProfile() {
    let fields = ProfileCreationFields.initial(devices: Self.pads)
    #expect(fields.deviceToken == Self.tokenA)
    #expect(fields.name == "Pad A")
    #expect(fields.proposedProfile(devices: Self.pads)?.device.vendorID == 0x0001)
  }

  @Test
  func withoutControllersNothingIsProposed() {
    let fields = ProfileCreationFields.initial(devices: [])
    #expect(fields.deviceToken == nil)
    #expect(fields.name.isEmpty)
    #expect(fields.proposedProfile(devices: []) == nil)
  }

  @Test
  func anUntouchedNameFollowsTheChosenController() {
    var fields = ProfileCreationFields.initial(devices: Self.pads)
    fields.selectDevice(Self.tokenB, in: Self.pads)
    #expect(fields.name == "Pad B")
    let profile = fields.proposedProfile(devices: Self.pads)
    #expect(profile?.device == RemappingDeviceScope(vendorID: 0x0003, productID: 0x0004))
  }

  @Test
  func anEditedNameStaysWhenAnotherControllerIsChosen() {
    var fields = ProfileCreationFields.initial(devices: Self.pads)
    fields.name = "Racing"
    fields.selectDevice(Self.tokenB, in: Self.pads)
    #expect(fields.name == "Racing")
    #expect(fields.deviceToken == Self.tokenB)
  }

  @Test
  func aBlankNameProposesNoProfile() {
    var fields = ProfileCreationFields.initial(devices: Self.pads)
    fields.name = "  "
    #expect(fields.proposedProfile(devices: Self.pads) == nil)
  }

  @Test
  func validationIsHiddenUntilAFieldIsEdited() {
    let initial = ProfileCreationFields.initial(devices: [])
    #expect(!initial.showsValidation(comparedTo: initial, isValid: false))

    var edited = initial
    edited.name = "Racing"
    #expect(edited.showsValidation(comparedTo: initial, isValid: false))
    #expect(!edited.showsValidation(comparedTo: initial, isValid: true))
  }
}
