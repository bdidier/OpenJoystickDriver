import Foundation
import OpenJoystickDriverKit

/// One labelled fact of the Controllers detail.
struct ControllerFact: Equatable, Identifiable {
  enum Kind: Hashable {
    case publication, serving, controllerProtocol, serialNumber, inputHealth
    case battery, chargingState, cableState
    case rumble, lighting, adaptiveTriggers, motion, touchContacts
    case unitID, parser, ownership, duplicateExposureRisk, outputOwner, record, controls
    case startupStatus, inputReportFormat, inputRecoveries
    case publicationAttempted, publicationCompleted
    case usbIdentifier, inputEndpoint, outputEndpoint
    case exclusiveOwner, alsoListedBySystem
  }

  let kind: Kind
  let label: String
  let value: OJDValue

  var id: Kind { kind }
}

/// The facts the Controllers detail lists for one controller, from the same service description
/// `ojd controller show` reads. A fact that applies but has no value shows "None"; a fact the
/// controller cannot have, such as an unreported battery or a motion sensor it lacks, is left out.
enum ControllerDetailFacts {
  /// The facts every user wants: what is published and how, the controller's state, and what it
  /// can do.
  static func general(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    let output = device.physicalOutputCapabilities
    let always = [
      fact(.publication, "cli.controller.show.labelPublication", publication(device)),
      fact(.serving, "ui.controllers.serving.label", .text(servingText(device))),
      fact(
        .controllerProtocol,
        "term.protocol",
        .text(device.protocolBinding.displayName)
      ),
      fact(.serialNumber, "term.serialNumber", serialNumber(device)),
      fact(.inputHealth, "cli.controller.show.labelInput", .text(inputHealthText(device))),
    ]
    let power = [
      fact(.battery, "ui.controllers.battery", battery(device)),
      fact(.chargingState, "ui.controllers.chargingState", chargingState(device)),
      fact(.cableState, "ui.controllers.cableState", cableState(device)),
    ]
    let capabilities = [
      fact(.rumble, "cli.controller.show.labelRumble", list(output.rumbleMotors.map(\.title))),
      fact(
        .lighting,
        "cli.controller.show.labelLighting",
        list(output.lightingFeatures.map(\.title))
      ),
      fact(
        .adaptiveTriggers,
        "ui.controllers.adaptiveTriggers",
        list(output.adaptiveTriggers.map(\.title))
      ),
      fact(
        .motion,
        "ui.controllers.motion",
        device.capabilities.motion ? .text(OJDLocalized.string("status.available")) : .none
      ),
      fact(
        .touchContacts,
        "ui.controllers.touchContacts",
        device.capabilities.touchContactCount > 0
          ? .text(String(device.capabilities.touchContactCount)) : .none
      ),
    ]
    let held =
      device.hidInputOwnership == .ownedByAnotherClient
      ? [
        fact(
          .exclusiveOwner,
          "ui.controllers.exclusiveOwner",
          .text(
            USBExclusiveOwner.heldMessage(for: device.inputOwner, localize: OJDLocalized.string)
          )
        )
      ] : []
    let listed =
      device.duplicateExposureRisk == .systemGameController
      ? [
        fact(
          .alsoListedBySystem,
          "ui.controllers.alsoListedBySystem",
          .text(OJDLocalized.string("status.controllerAlsoListedBySystem"))
        )
      ] : []
    return always + held + listed + (power + capabilities).filter { $0.value != .none }
  }

  /// The technical facts, shown under Advanced: identifiers, the parser (the binding that parses
  /// the controller's input, in its `ojd` spelling, such as `xbox-xusb:receiver`), ownership, the
  /// record, publication timing, and the controls the parser emits. `record` is the controller
  /// model's effective record, if one matches.
  static func advanced(
    for device: ApplicationServiceDeviceDescription,
    record: ControllerRecord?
  ) -> [ControllerFact] {
    let health = device.inputHealth
    let publication = device.publication
    let now = DispatchTime.now().uptimeNanoseconds
    let optional = [
      fact(
        .outputOwner,
        "cli.controller.show.labelOutputOwner",
        device.physicalOutputOwner == .system
          ? .text(OJDLocalized.string("platform.macos.cli.controller.show.outputOwnerMacos"))
          : .none
      ),
      fact(
        .controls,
        "cli.controller.show.labelControls",
        list(
          Control.allCases.filter(device.capabilities.controls.contains).map {
            RuntimePresentation.sourceLabel(.button($0))
          }
        )
      ),
      fact(
        .startupStatus,
        "ui.controllers.startupStatus",
        OJDValue(device.startupCommandStatus)
      ),
      fact(.inputReportFormat, "ui.controllers.inputReportFormat", OJDValue(health.reportFormat)),
      fact(
        .inputRecoveries,
        "ui.controllers.inputRecoveries",
        health.recoveryCount > 0 ? .text(String(health.recoveryCount)) : .none
      ),
      fact(
        .publicationAttempted,
        "ui.controllers.publicationAttempted",
        age(publication?.lastAttemptedNanoseconds, now: now)
      ),
      fact(
        .publicationCompleted,
        "ui.controllers.publicationCompleted",
        age(publication?.lastCompletedNanoseconds, now: now)
      ),
    ].filter { $0.value != .none }
    return [
      fact(.unitID, "cli.controller.show.labelUnit", .reported(device.portKey?.rawValue)),
      fact(.parser, "term.parser", .reported(device.protocolBinding.commandLineName)),
      fact(.ownership, "cli.controller.show.labelOwnership", .text(ownershipText(device))),
      fact(
        .duplicateExposureRisk,
        "ui.controllers.duplicateExposureRisk",
        .text(duplicateExposureText(device.duplicateExposureRisk))
      ),
      fact(.record, "cli.controller.show.labelRecord", .text(recordText(record))),
    ] + optional + [
      fact(.usbIdentifier, "ui.controllers.usbIdentifier", usbIdentifier(device)),
      fact(.inputEndpoint, "term.inputEndpoint", .endpoint(device.inputEndpoint)),
      fact(.outputEndpoint, "term.outputEndpoint", .endpoint(device.outputEndpoint)),
    ]
  }

  /// The Automatic choice of the Virtual HID profile picker. It names the profile the service
  /// selected on its own, so the picker is the one place the published profile is shown; it is
  /// plain "Automatic" while an override is the selection or when no profile is selected.
  static func automaticProfileLabel(_ device: ApplicationServiceDeviceDescription) -> String {
    let automatic = OJDLocalized.string("ui.mapping.automatic")
    guard let status = device.virtualHIDProfile, let profile = status.profile,
      status.source != .override
    else { return automatic }
    return OJDLocalized.formatted(
      "ui.virtualProfile.automaticSelected",
      profile.identity.productName
    )
  }

  /// Whether a virtual device publishes the controller, why not, and for a failed send the
  /// failure text, localized; "None" when the service reports none.
  static func publication(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    device.publication.map { .text(publicationText($0)) } ?? .none
  }

  /// The route, with why it publishes nothing when it does not.
  static func servingText(_ device: ApplicationServiceDeviceDescription) -> String {
    guard let reason = device.servingDecision.route.disabledReason else {
      return device.servingRouteLabel
    }
    return OJDLocalized.formatted(
      "ui.controllers.serving.withReason",
      device.servingRouteLabel,
      OJDLocalized.string(ControllerDetailLabels.servingReasonKey(reason))
    )
  }

  /// The input health state, with its failure reason when it has one.
  static func inputHealthText(_ device: ApplicationServiceDeviceDescription) -> String {
    let state = OJDLocalized.string(inputHealthKey(device.inputHealth.state))
    guard let reason = device.inputHealth.failureReason else { return state }
    return OJDLocalized.formatted(
      "ui.controllers.inputHealth.withReason",
      state,
      OJDLocalized.string(ControllerDetailLabels.inputHealthReasonKey(reason))
    )
  }

  static func ownershipText(_ device: ApplicationServiceDeviceDescription) -> String {
    OJDLocalized.formatted(
      "ui.controllers.ownership.value",
      OJDLocalized.string(ControllerDetailLabels.discoveryKey(device.discoverySource)),
      OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(device.physicalOwnership)),
      OJDLocalized.string(ControllerDetailLabels.hidInputOwnershipKey(device.hidInputOwnership))
    )
  }

  /// The duplicate-exposure concern of the physical ownership, localized.
  static func duplicateExposureText(_ risk: DuplicateExposureRisk) -> String {
    switch risk {
    case .none: return OJDLocalized.string("status.none")
    case .systemHIDVisible:
      return OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(.systemHIDVisible))
    case .upstreamVirtualDevice:
      return OJDLocalized.string(
        ControllerDetailLabels.physicalOwnershipKey(.upstreamVirtualDevice)
      )
    case .systemGameController: return OJDLocalized.string("ui.controllers.alsoListedBySystem")
    case .unknownOwnership:
      return OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(.unknown))
    }
  }

  /// The record layer, and the file when a user or package file sets the record.
  static func recordText(_ record: ControllerRecord?) -> String {
    guard let record else { return OJDLocalized.string("cli.controller.show.recordNone") }
    guard let file = record.file else {
      return OJDLocalized.string("cli.controller.show.recordBundled")
    }
    return OJDLocalized.formatted("cli.controller.show.recordUser", file.path)
  }

  private static func inputHealthKey(_ state: ControllerInputHealthState) -> String {
    switch state {
    case .healthy: return "ui.controllers.inputHealth.healthy"
    case .stale: return "ui.controllers.inputHealth.stale"
    case .waitingForNeutral: return "ui.controllers.inputHealth.waitingForNeutral"
    }
  }

  private static func publicationKey(_ state: ApplicationServicePublicationStatus.State) -> String {
    switch state {
    case .published: return "ui.controllers.publication.published"
    case .notPublished: return "ui.controllers.publication.notPublished"
    case .failed: return "ui.controllers.publication.failed"
    }
  }

  /// The record layer that sets the controller's server, by the name the Library gives it.
  static func serverSourceText(_ record: ControllerRecord) -> String {
    (record.fieldLayers["server"] ?? .driver).libraryTitle
  }

  static func publicationText(_ publication: ApplicationServicePublicationStatus) -> String {
    let state = OJDLocalized.string(publicationKey(publication.state))
    let detail: String
    switch publication.state {
    case .published: return state
    case .notPublished:
      guard let reason = publication.reason else { return state }
      detail = OJDLocalized.string(ControllerDetailLabels.notPublishedReasonKey(reason))
    case .failed:
      guard let failure = publication.failure else { return state }
      detail = OJDLocalized.formatted("ui.controllers.publication.failedSend", failure)
    }
    return OJDLocalized.formatted("ui.controllers.publication.withReason", state, detail)
  }

  static func serialNumber(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    .reported(device.serialNumber)
  }

  static func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    .usbIdentifier(vendorID: device.vendorID, productID: device.productID)
  }

  static func battery(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    OJDValue(device.connectionState?.power.battery.percentageText)
  }

  static func chargingState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.charging ?? .unknown {
    case .discharging: return .text(OJDLocalized.string("ui.controllers.discharging"))
    case .charging: return .text(OJDLocalized.string("ui.controllers.charging"))
    case .full: return .text(OJDLocalized.string("ui.controllers.batteryFull"))
    case .notChargeable: return .text(OJDLocalized.string("ui.controllers.notChargeable"))
    case .unknown: return .none
    }
  }

  static func cableState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.wiredPower {
    case true?:
      return .text(OJDLocalized.string("ui.settings.notifications.controllerConnectedShort"))
    case false?:
      return .text(OJDLocalized.string("ui.settings.notifications.controllerDisconnectedShort"))
    case nil: return .none
    }
  }

  /// How long before `now` the system uptime `nanoseconds` was, as relative text.
  static func age(_ nanoseconds: UInt64?, now: UInt64) -> OJDValue {
    guard let nanoseconds, nanoseconds <= now else { return .none }
    let seconds = Double(now - nanoseconds) / 1_000_000_000
    return .text(
      RelativeDateTimeFormatter().localizedString(
        for: Date(timeIntervalSinceNow: -seconds),
        relativeTo: Date()
      )
    )
  }

  private static func fact(
    _ kind: ControllerFact.Kind,
    _ key: String,
    _ value: OJDValue
  )
    -> ControllerFact
  {
    ControllerFact(kind: kind, label: OJDLocalized.string(key), value: value)
  }

  /// The comma-separated names, or no value when there are none.
  private static func list(_ names: [String]) -> OJDValue {
    names.isEmpty ? .none : .text(names.joined(separator: ", "))
  }
}
