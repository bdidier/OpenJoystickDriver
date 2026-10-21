import Foundation
import OpenJoystickDriverKit

/// One labelled fact of the Controllers detail.
struct ControllerFact: Equatable, Identifiable {
  enum Kind: Hashable {
    case persona, publication, serving, controllerProtocol, serialNumber, inputHealth
    case battery, chargingState, cableState
    case rumble, lighting, adaptiveTriggers, motion, touchContacts
    case unitID, ownership, duplicateExposureRisk, outputOwner, record, controls
    case startupStatus, inputReportFormat, inputRecoveries
    case publicationAttempted, publicationCompleted
    case usbIdentifier, inputEndpoint, outputEndpoint
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
      fact(.persona, "cli.controller.show.label.persona", persona(device)),
      fact(.publication, "cli.controller.show.label.publication", publication(device)),
      fact(.serving, "controllers.serving.label", .text(servingText(device))),
      fact(.controllerProtocol, "common.protocol", .text(device.protocolBinding.displayLabel)),
      fact(.serialNumber, "common.serialNumber", serialNumber(device)),
      fact(.inputHealth, "cli.controller.show.label.input", .text(inputHealthText(device))),
    ]
    let power = [
      fact(.battery, "controllers.battery", battery(device)),
      fact(.chargingState, "controllers.chargingState", chargingState(device)),
      fact(.cableState, "controllers.cableState", cableState(device)),
    ]
    let capabilities = [
      fact(.rumble, "cli.controller.show.label.rumble", list(output.rumbleMotors.map(\.title))),
      fact(
        .lighting,
        "cli.controller.show.label.lighting",
        list(output.lightingFeatures.map(\.title))
      ),
      fact(
        .adaptiveTriggers,
        "controllers.adaptiveTriggers",
        list(output.adaptiveTriggers.map(\.title))
      ),
      fact(
        .motion,
        "controllers.motion",
        device.capabilities.motion ? .text(OJDLocalized.string("common.available")) : .none
      ),
      fact(
        .touchContacts,
        "controllers.touchContacts",
        device.capabilities.touchContactCount > 0
          ? .text(String(device.capabilities.touchContactCount)) : .none
      ),
    ]
    return always + (power + capabilities).filter { $0.value != .none }
  }

  /// The technical facts, shown under Advanced: identifiers, ownership, the record, publication
  /// timing, and the controls the parser emits. `record` is the controller model's effective
  /// record, if one matches.
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
        "cli.controller.show.label.output_owner",
        device.physicalOutputOwner == .system
          ? .text(OJDLocalized.string("cli.controller.show.output_owner.macos")) : .none
      ),
      fact(
        .controls,
        "cli.controller.show.label.controls",
        list(
          Control.allCases.filter(device.capabilities.controls.contains).map {
            RuntimePresentation.sourceLabel(.button($0))
          }
        )
      ),
      fact(
        .startupStatus,
        "controllers.startupStatus",
        OJDValue(device.startupCommandStatus)
      ),
      fact(.inputReportFormat, "controllers.inputReportFormat", OJDValue(health.reportFormat)),
      fact(
        .inputRecoveries,
        "controllers.inputRecoveries",
        health.recoveryCount > 0 ? .text(String(health.recoveryCount)) : .none
      ),
      fact(
        .publicationAttempted,
        "controllers.publicationAttempted",
        age(publication?.lastAttemptedNanoseconds, now: now)
      ),
      fact(
        .publicationCompleted,
        "controllers.publicationCompleted",
        age(publication?.lastCompletedNanoseconds, now: now)
      ),
    ].filter { $0.value != .none }
    return [
      fact(.unitID, "cli.controller.show.label.unit", .reported(device.portKey?.rawValue)),
      fact(.ownership, "cli.controller.show.label.ownership", .text(ownershipText(device))),
      fact(
        .duplicateExposureRisk,
        "controllers.duplicateExposureRisk",
        .text(CommandLineName.kebab(device.duplicateExposureRisk.rawValue))
      ),
      fact(.record, "cli.controller.show.label.record", .text(recordText(record))),
    ] + optional + [
      fact(.usbIdentifier, "controllers.usbIdentifier", usbIdentifier(device)),
      fact(.inputEndpoint, "common.inputEndpoint", .endpoint(device.inputEndpoint)),
      fact(.outputEndpoint, "common.outputEndpoint", .endpoint(device.outputEndpoint)),
    ]
  }

  /// The virtual HID profile the service selected for the controller, as `ojd controller show`
  /// prints `serving.persona`; "None" when none is selected. Whether it is published is the
  /// separate ``publication(_:)``.
  static func persona(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    guard let selection = device.servingDecision.selection else { return .none }
    return .text(selection.profileID.identity.publishedUSBIdentityLabel)
  }

  /// Whether a virtual device publishes the controller and why not, as `publication.state` and
  /// `publication.reason`; "None" when the service reports none.
  static func publication(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    device.publication.map { .text(publicationText($0)) } ?? .none
  }

  /// The route, with why it publishes nothing when it does not.
  static func servingText(_ device: ApplicationServiceDeviceDescription) -> String {
    guard let reason = device.servingDecision.route.disabledReason else {
      return device.servingRouteLabel
    }
    return "\(device.servingRouteLabel) (\(CommandLineName.kebab(reason.rawValue)))"
  }

  /// The input health state, with its failure reason when it has one.
  static func inputHealthText(_ device: ApplicationServiceDeviceDescription) -> String {
    let state = OJDLocalized.string(inputHealthKey(device.inputHealth.state))
    guard let reason = device.inputHealth.failureReason else { return state }
    return "\(state) (\(CommandLineName.kebab(reason.rawValue)))"
  }

  static func ownershipText(_ device: ApplicationServiceDeviceDescription) -> String {
    OJDLocalized.formatted(
      "cli.controller.show.ownership",
      CommandLineName.kebab(device.discoverySource.rawValue),
      CommandLineName.kebab(device.physicalOwnership.rawValue),
      CommandLineName.kebab(device.hidInputOwnership.rawValue)
    )
  }

  /// The record layer, and the file when a user or package file sets the record.
  static func recordText(_ record: ControllerRecord?) -> String {
    guard let record else { return OJDLocalized.string("cli.controller.show.record.none") }
    guard let file = record.file else {
      return OJDLocalized.string("cli.controller.show.record.bundled")
    }
    return OJDLocalized.formatted("cli.controller.show.record.user", file.path)
  }

  private static func inputHealthKey(_ state: ControllerInputHealthState) -> String {
    switch state {
    case .healthy: return "controllers.inputHealth.healthy"
    case .stale: return "controllers.inputHealth.stale"
    case .waitingForNeutral: return "controllers.inputHealth.waitingForNeutral"
    }
  }

  private static func publicationKey(_ state: ApplicationServicePublicationStatus.State) -> String {
    switch state {
    case .published: return "controllers.publication.published"
    case .notPublished: return "controllers.publication.notPublished"
    case .failed: return "controllers.publication.failed"
    }
  }

  static func publicationText(_ publication: ApplicationServicePublicationStatus) -> String {
    let state = OJDLocalized.string(publicationKey(publication.state))
    guard
      let detail = publication.reason.map({ CommandLineName.kebab($0.rawValue) })
        ?? publication.failure
    else { return state }
    return "\(state) (\(detail))"
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
    case .discharging: return .text(OJDLocalized.string("controllers.discharging"))
    case .charging: return .text(OJDLocalized.string("controllers.charging"))
    case .full: return .text(OJDLocalized.string("controllers.batteryFull"))
    case .notChargeable: return .text(OJDLocalized.string("controllers.notChargeable"))
    case .unknown: return .none
    }
  }

  static func cableState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.wiredPower {
    case true?: return .text(OJDLocalized.string("settings.controllerConnectedShort"))
    case false?: return .text(OJDLocalized.string("settings.controllerDisconnectedShort"))
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
