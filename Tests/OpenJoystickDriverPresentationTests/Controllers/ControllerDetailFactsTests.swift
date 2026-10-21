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
      recordServer: .system,
      recordAccessRoute: .system,
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
      kinds == [.publication, .serving, .controllerProtocol, .serialNumber, .inputHealth]
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
  func missingSerialNumberShowsNone() {
    let facts = ControllerDetailFacts.general(for: device())
    #expect(Self.value(.serialNumber, in: facts) == OJDValue.none)
  }

  @Test
  func theSelectedProfileShowsWhetherOrNotItIsPublished() {
    let published = ApplicationServicePublicationStatus.published(target: .sdlCompatible)
    let notPublished = ApplicationServicePublicationStatus.notPublished(
      .noInputYet,
      target: .sdlCompatible
    )
    let failed = ApplicationServicePublicationStatus.failed("send failed", target: .sdlCompatible)
    let reason = OJDLocalized.string("controllers.publication.reason.noInputYet")
    let failure = OJDLocalized.formatted("controllers.publication.failedSend", "send failed")
    let withReason = { (state: String, detail: String) in
      OJDLocalized.formatted("controllers.publication.withReason", state, detail)
    }
    for (publication, text) in [
      (published, OJDLocalized.string("controllers.publication.published")),
      (
        notPublished,
        withReason(OJDLocalized.string("controllers.publication.notPublished"), reason)
      ),
      (failed, withReason(OJDLocalized.string("controllers.publication.failed"), failure)),
    ] {
      let facts = ControllerDetailFacts.general(
        for: device(override: .sdlCompatible, publication: publication)
      )
      #expect(Self.value(.publication, in: facts) == .text(text))
    }
    let unreported = ControllerDetailFacts.general(for: device(override: .sdlCompatible))
    #expect(Self.value(.publication, in: unreported) == OJDValue.none)
  }

  @Test
  func theProfileIsPublishedOnlyInThePicker() {
    let facts = ControllerDetailFacts.general(for: device(override: .sdlCompatible))
    #expect(!facts.map(\.label).contains(OJDLocalized.string("cli.controller.show.label.persona")))
  }

  @Test
  func theAutomaticChoiceNamesTheProfileTheServiceSelected() {
    var pad = device()
    pad.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: .automatic,
      override: nil,
      unavailable: false
    )
    #expect(
      ControllerDetailFacts.automaticProfileLabel(pad)
        == "Automatic (\(VirtualHIDProfileID.generic.identity.productName))"
    )
  }

  @Test
  func theAutomaticChoiceIsPlainWithAnOverrideOrWithoutASelection() {
    #expect(ControllerDetailFacts.automaticProfileLabel(device(override: .generic)) == "Automatic")
    #expect(
      ControllerDetailFacts.automaticProfileLabel(device(ownership: .systemGamepad)) == "Automatic"
    )
  }

  @Test
  func identifiersEndpointsAndOwnershipAreAdvanced() {
    let facts = ControllerDetailFacts.advanced(for: device(), record: nil)
    #expect(Self.value(.usbIdentifier, in: facts) == .text("1234:5678"))
    #expect(Self.value(.inputEndpoint, in: facts) == OJDValue.none)
    #expect(Self.value(.unitID, in: facts) == OJDValue.none)
    #expect(
      Self.value(.ownership, in: facts)
        == .text(
          OJDLocalized.formatted(
            "controllers.ownership.value",
            OJDLocalized.string("controllers.discovery.rawUSB"),
            OJDLocalized.string("controllers.physicalOwnership.unknown"),
            OJDLocalized.string("controllers.hidInputOwnership.unknown")
          )
        )
    )
    #expect(
      Self.value(.duplicateExposureRisk, in: facts)
        == .text(OJDLocalized.string("controllers.physicalOwnership.unknown"))
    )
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
    #expect(
      Self.value(.inputHealth, in: facts)
        == .text(OJDLocalized.string("controllers.inputHealth.healthy"))
    )
  }

  @Test
  func everyStateTheDetailNamesHasEnglishText() {
    var keys: [String] = []
    keys += ControllerOwnershipObservation.allCases.map(ControllerDetailLabels.physicalOwnershipKey)
    keys += [
      HIDInputOwnership.unknown, .exclusive, .shared, .accessDenied, .ownedByAnotherClient,
      .acquisitionFailed,
    ]
    .map(ControllerDetailLabels.hidInputOwnershipKey)
    keys += [DeviceDiscoverySource.hid, .rawUSB].map(ControllerDetailLabels.discoveryKey)
    keys += OutputDisabledReason.allCases.map(ControllerDetailLabels.servingReasonKey)
    keys += [ControllerInputHealthFailureReason.missingReports, .freshnessNotAdvancing]
      .map(ControllerDetailLabels.inputHealthReasonKey)
    for key in keys { #expect(OJDLocalized.string(key) != key, "\(key)") }
    for reason in ApplicationServicePublicationStatus.NotPublishedReason.allCases {
      let key = ControllerDetailLabels.notPublishedReasonKey(reason)
      #expect(OJDLocalized.string(key) != key, "\(key)")
    }
  }

  @Test
  func everyWirelessDisconnectFailureHasLocalizedText() {
    for failure in [
      WirelessControllerDisconnectFailure.notFound, .notBluetooth, .bluetoothLEUnsupported,
      .missingAddress, .disconnectFailed, .timedOut,
    ] {
      let text = ControllerDetailLabels.wirelessDisconnectFailureText(failure)
      #expect(!text.contains("controllers.disconnectWireless"))
      #expect(!text.contains(failure.rawValue))
    }
  }

  @Test
  func theDuplicateExposureRiskIsNamedForEveryCase() {
    #expect(
      ControllerDetailFacts.duplicateExposureText(.none) == OJDLocalized.string("common.none")
    )
    for risk in [DuplicateExposureRisk.systemHIDVisible, .upstreamVirtualDevice, .unknownOwnership]
    {
      #expect(!ControllerDetailFacts.duplicateExposureText(risk).contains("controllers."))
    }
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
      ControllerDetailFacts.publicationText(ApplicationServicePublicationStatus.published())
        == OJDLocalized.string("controllers.publication.published")
    )
    #expect(
      ControllerDetailFacts.publicationText(
        ApplicationServicePublicationStatus.notPublished(.noInputYet)
      )
        == OJDLocalized.formatted(
          "controllers.publication.withReason",
          OJDLocalized.string("controllers.publication.notPublished"),
          OJDLocalized.string("controllers.publication.reason.noInputYet")
        )
    )
    #expect(
      ControllerDetailFacts.inputHealthText(device())
        == OJDLocalized.string("controllers.inputHealth.healthy")
    )
  }
}
