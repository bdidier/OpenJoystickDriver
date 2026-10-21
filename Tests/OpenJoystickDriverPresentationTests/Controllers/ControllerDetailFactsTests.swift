import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ControllerDetailFactsTests {
  private func device(
    power: ControllerConnectionState.Power? = nil,
    ownership: ControllerOwnershipObservation = .unknown,
    override: VirtualHIDProfileID? = nil,
    publication: ApplicationServicePublicationStatus? = nil,
    output: PhysicalControllerOutputCapabilities = .none,
    motion: Bool = false
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      physicalOwnership: ownership,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: output,
      capabilities: ControllerCapabilities(controls: [], motion: motion),
      connectionState: power.map {
        ControllerConnectionState(transport: nil, backend: .hid, isConnected: true, power: $0)
      },
      sessionToken: .fixture("facts-device")
    )
    device.virtualHIDProfile = override.map {
      ApplicationServiceVirtualHIDProfileStatus(
        profile: $0,
        source: .override,
        override: $0,
        unavailable: false
      )
    }
    device.publication = publication
    return device
  }

  private static func value(
    _ kind: ControllerFact.Kind,
    in facts: [ControllerFact]
  ) -> OJDValue? {
    facts.first { $0.kind == kind }?.value
  }

  @Test
  func unknownBatteryChargingAndCableAreHidden() {
    let kinds = ControllerDetailFacts.general(for: device(power: .unknown)).map(\.kind)
    #expect(
      kinds == [.persona, .publication, .serving, .controllerProtocol, .serialNumber, .inputHealth]
    )
    #expect(ControllerDetailFacts.general(for: device()).map(\.kind) == kinds)
  }

  @Test
  func reportedPowerFactsAreListed() {
    let power = ControllerConnectionState.Power(
      charging: .charging,
      battery: BatteryLevel(percentage: 80...80),
      wiredPower: true
    )
    let facts = ControllerDetailFacts.general(for: device(power: power))
    #expect(facts.map(\.kind).suffix(3) == [.battery, .chargingState, .cableState])
    #expect(Self.value(.battery, in: facts) == .text("80%"))
  }

  @Test
  func capabilitiesTheControllerLacksAreHidden() {
    let none = ControllerDetailFacts.general(for: device()).map(\.kind)
    #expect(!none.contains(.rumble) && !none.contains(.lighting) && !none.contains(.motion))
    #expect(!none.contains(.adaptiveTriggers) && !none.contains(.touchContacts))

    let facts = ControllerDetailFacts.general(
      for: device(
        output: PhysicalControllerOutputCapabilities(
          rumbleMotors: [.lowFrequency, .highFrequency],
          lightingFeatures: [.programmableColor],
          adaptiveTriggers: [.left]
        ),
        motion: true
      )
    )
    #expect(Self.value(.rumble, in: facts) == .text("Left main, Right main"))
    #expect(Self.value(.lighting, in: facts) == .text("Color"))
    #expect(Self.value(.adaptiveTriggers, in: facts) == .text("Left trigger"))
    #expect(Self.value(.motion, in: facts) == .text("Available"))
  }

  @Test
  func missingSerialNumberShowsTheHyphen() {
    let facts = ControllerDetailFacts.general(for: device())
    #expect(Self.value(.serialNumber, in: facts) == OJDValue.none)
  }

  @Test
  func theSelectedProfileShowsWhetherOrNotItIsPublished() {
    let label = "Xbox Wireless Controller (045E:02FD)"
    let published = ApplicationServicePublicationStatus(state: .published, target: .sdlCompatible)
    let notPublished = ApplicationServicePublicationStatus(
      state: .notPublished,
      reason: "noInputYet",
      target: .sdlCompatible
    )
    let failed = ApplicationServicePublicationStatus(
      state: .failed,
      reason: "send failed",
      target: .sdlCompatible
    )
    for (publication, text) in [
      (published, "Published"), (notPublished, "Not published (noInputYet)"),
      (failed, "Failed (send failed)"),
    ] {
      let facts = ControllerDetailFacts.general(
        for: device(override: .sdlCompatible, publication: publication)
      )
      #expect(Self.value(.persona, in: facts) == .text(label))
      #expect(Self.value(.publication, in: facts) == .text(text))
    }
    let unreported = ControllerDetailFacts.general(for: device(override: .sdlCompatible))
    #expect(Self.value(.persona, in: unreported) == .text(label))
    #expect(Self.value(.publication, in: unreported) == OJDValue.none)
  }

  @Test
  func personaIsTheHyphenWithoutASelection() {
    let system = device(ownership: .systemGamepad)
    #expect(system.servingDecision.selection == nil)
    #expect(Self.value(.persona, in: ControllerDetailFacts.general(for: system)) == OJDValue.none)
  }

  @Test
  func identifiersEndpointsAndOwnershipAreAdvanced() {
    let facts = ControllerDetailFacts.advanced(for: device(), record: nil)
    #expect(Self.value(.usbIdentifier, in: facts) == .text("1234:5678"))
    #expect(Self.value(.inputEndpoint, in: facts) == OJDValue.none)
    #expect(Self.value(.unitID, in: facts) == OJDValue.none)
    #expect(
      Self.value(.ownership, in: facts)
        == .text("route raw-usb, physical unknown, HID input unknown")
    )
    #expect(Self.value(.duplicateExposureRisk, in: facts) == .text("unknown-ownership"))
    #expect(Self.value(.record, in: facts) == .text("none (no record matches)"))
  }

  @Test
  func advancedFactsThatDoNotApplyAreHidden() {
    let kinds = ControllerDetailFacts.advanced(for: device(), record: nil).map(\.kind)
    #expect(!kinds.contains(.outputOwner))
    #expect(!kinds.contains(.startupStatus))
    #expect(!kinds.contains(.inputRecoveries))
    #expect(!kinds.contains(.publicationAttempted))
  }

  @Test
  func inputHealthNamesTheStateAndItsFailure() {
    let facts = ControllerDetailFacts.general(for: device())
    #expect(Self.value(.inputHealth, in: facts) == .text("Healthy"))
  }
}

extension ControllerDetailFactsTests {
  @Test
  func tuningRowsListOnlyValuesALayerSets() throws {
    let model = ControllerModelID(vendorID: 0x045E, productID: 0x02FD)
    let record = try #require(ControllerRecordSet.bundled.records[model])
    let rows = ControllerTuningRows.rows(for: record, activeProfile: nil)
    #expect(rows.map(\.name) == ControllerTuning.Key.allCases.map(\.rawValue))
    for (row, entry) in zip(rows, record.tuningValues) {
      if entry.value == nil {
        #expect(row.text == OJDLocalized.string("cli.config.show.unset"))
      } else {
        #expect(row.layer == CommandLineName.kebab(entry.layer.rawValue))
        #expect(row.text == "\(row.value) (\(row.layer ?? ""))")
      }
    }
  }

  @Test
  func publicationAndInputHealthShowLocalizedWords() {
    #expect(
      ControllerDetailFacts.publicationText(ApplicationServicePublicationStatus(state: .published))
        == OJDLocalized.string("controllers.publication.published")
    )
    #expect(
      ControllerDetailFacts.publicationText(
        ApplicationServicePublicationStatus(state: .notPublished, reason: "noInputYet")
      ) == "\(OJDLocalized.string("controllers.publication.notPublished")) (noInputYet)"
    )
    #expect(
      ControllerDetailFacts.inputHealthText(device())
        == OJDLocalized.string("controllers.inputHealth.healthy")
    )
  }
}
