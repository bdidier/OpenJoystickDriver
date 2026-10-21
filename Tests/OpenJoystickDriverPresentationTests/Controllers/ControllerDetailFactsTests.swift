import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ControllerDetailFactsTests {
  private func device(
    power: ControllerConnectionState.Power? = nil,
    ownership: ControllerOwnershipObservation = .unknown
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      physicalOwnership: ownership,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      connectionState: power.map {
        ControllerConnectionState(transport: nil, backend: .hid, isConnected: true, power: $0)
      },
      sessionToken: .fixture("facts-device")
    )
  }

  @Test
  func unknownBatteryChargingAndCableAreHidden() {
    let kinds = ControllerDetailFacts.general(for: device(power: .unknown)).map(\.kind)
    #expect(kinds == [.publishedAs, .serving, .controllerProtocol, .serialNumber])
    #expect(ControllerDetailFacts.general(for: device()).map(\.kind) == kinds)
  }

  @Test
  func reportedPowerFactsAreListed() {
    let power = ControllerConnectionState.Power(
      charging: .charging,
      battery: BatteryLevel(percentage: 80...80),
      wiredPower: true
    )
    let kinds = ControllerDetailFacts.general(for: device(power: power)).map(\.kind)
    #expect(kinds.suffix(3) == [.battery, .chargingState, .cableState])
  }

  @Test
  func missingSerialNumberShowsTheHyphen() {
    let serial = ControllerDetailFacts.general(for: device()).first { $0.kind == .serialNumber }
    #expect(serial?.value == OJDValue.none)
  }

  @Test
  func identifiersAndEndpointsAreAdvanced() {
    let facts = ControllerDetailFacts.advanced(for: device())
    #expect(facts.map(\.kind) == [.usbIdentifier, .inputEndpoint, .outputEndpoint])
    #expect(facts.map(\.value) == [.text("1234:5678"), .none, .none])
  }

  @Test
  func publishedAsShowsThePublishedProfileOnce() {
    var published = device()
    published.publication = ApplicationServicePublicationStatus(
      state: .published,
      target: .sdlCompatible
    )
    #expect(ControllerDetailFacts.publishedAs(published) == .text(published.publishedIdentityLabel))
    let count = ControllerDetailFacts.general(for: published).filter {
      $0.value == .text(published.publishedIdentityLabel)
    }.count
    #expect(count == 1)
  }

  @Test
  func publishedAsShowsTheHyphenWhenNothingIsPublishedOrSelected() {
    let system = device(ownership: .systemGamepad)
    #expect(system.servingDecision.selection == nil)
    #expect(ControllerDetailFacts.publishedAs(system) == .none)
  }
}
