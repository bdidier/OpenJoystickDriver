import Foundation

@testable import OpenJoystickDriverKit

/// Renders a record's behavior as text built only from resolved values and the explicit labels in
/// `EquivalenceSnapshotTests+CatalogLabels.swift`.
extension EquivalenceSnapshotCatalogTests {
  static func write(_ write: PhysicalOutputWrite) -> String {
    switch write {
    case .usb(let packet, let tolerates):
      "usb ep=\(packet.endpoint) timeoutMs=\(packet.timeoutMilliseconds)"
        + " tolerated=\(tolerates) \(hex(packet.bytes))"
    case .hidOutput(let report): "hid-output id=\(report.reportID) \(hex(report.bytes))"
    case .hidFeature(let report): "hid-feature id=\(report.reportID) \(hex(report.bytes))"
    }
  }

  static func writes(_ name: String, _ writes: [PhysicalOutputWrite]) -> [String] {
    writes.isEmpty ? [] : writes.enumerated().map { "\(name)[\($0.offset)] \(write($0.element))" }
  }

  /// The tuning values the record sets, by explicit key label.
  static func tuning(_ tuning: ControllerTuning) -> String {
    let set = ControllerTuning.Key.allCases.compactMap { key in
      tuning.text(of: key).map { "\(label(key))=\($0)" }
    }
    return set.isEmpty ? "-" : set.sorted().joined(separator: ",")
  }

  private static func field(_ field: ReportBitField) -> String {
    "\(field.byte)&\(String(format: "%02X", field.mask))"
  }

  private static func layoutLines(_ layout: ControllerInputLayout) -> [String] {
    var lines = [
      "inputLayout reportID=\(layout.reportID.map(String.init) ?? "-")"
        + " minimumLength=\(layout.minimumLength)"
    ]
    for button in layout.buttons {
      lines.append(
        "inputLayout button \(button.control.rawValue)"
          + " \(button.fields.map(field).joined(separator: "|"))"
      )
    }
    for axis in layout.axes {
      lines.append(
        "inputLayout axis \(axis.control.rawValue) byte=\(axis.byte) bits=\(axis.bits)"
          + " signed=\(axis.isSigned) range=\(axis.minimum)...\(axis.maximum)"
          + " inverted=\(axis.isInverted)"
      )
    }
    for source in layout.hat {
      switch source {
      case .eightWay(let hat, let neutralUntilNonzero):
        lines.append(
          "inputLayout hat eight-way \(field(hat)) neutralUntilNonzero=\(neutralUntilNonzero)"
        )
      case .directions(let up, let right, let down, let left):
        lines.append(
          "inputLayout hat directions up=\(field(up)) right=\(field(right))"
            + " down=\(field(down)) left=\(field(left))"
        )
      case .table(let hat, let directions):
        let entries = directions.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }
        lines.append("inputLayout hat table \(field(hat)) \(entries.joined(separator: ","))")
      }
    }
    for (name, trigger) in [("left", layout.leftTrigger), ("right", layout.rightTrigger)] {
      guard let trigger else { continue }
      lines.append(
        "inputLayout trigger \(name) byte=\(trigger.byte.map(String.init) ?? "-")"
          + " button=\(trigger.button.map(field) ?? "-")"
      )
    }
    return lines
  }

  private static func driverLines(_ record: ControllerRecord) -> [String] {
    let profile = record.profile
    let variant =
      profile.physicalProtocolVariant
      ?? (profile.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
    guard
      case .success(let driver) = ProtocolDriverRegistry.makeUnobservedDriver(
        protocolID: profile.physicalProtocolID,
        variant: variant,
        record: profile,
        model: record.model,
        transportProfile: profile.transportProfile
      )
    else { return ["driver none"] }
    let controls = ProtocolDriverRegistry().capabilities(
      driver.capabilities.normalized,
      record: profile
    )
    let output = driver.outputCapabilities
    let plan = driver.sessionPlan
    func milliseconds(_ nanoseconds: UInt64?) -> String {
      nanoseconds.map { String($0 / 1_000_000) } ?? "-"
    }
    // The snapshot predates recovery being Switch 1 only. A plan with no recovery printed the
    // plan's former default of 200 ms and 2 rounds, and the snapshot keeps that spelling.
    let recoveryInterval =
      plan.hasStartupRecovery ? plan.hidStartupRecoveryIntervalNanoseconds : 200_000_000
    let recoveryRounds = plan.hasStartupRecovery ? plan.hidStartupRecoveryRounds : 2
    var lines = [
      "controls [\(labels(controls.controls))]",
      "output rumble=[\(output.rumbleMotors.map(label).joined(separator: ","))]"
        + " binary=[\(output.binaryRumbleMotors.map(label).joined(separator: ","))]"
        + " lighting=[\(output.lightingFeatures.map(label).joined(separator: ","))]"
        + " adaptiveTriggers=[\(output.adaptiveTriggers.map(label).joined(separator: ","))]",
      "session usbStartupMs=\(milliseconds(plan.usbStartupIntervalNanoseconds))"
        + " usbKeepAliveMs=\(milliseconds(plan.usbKeepAliveIntervalNanoseconds))"
        + " hidStartupMs=\(milliseconds(plan.hidStartupIntervalNanoseconds))"
        + " hidKeepAliveMs=\(milliseconds(plan.hidKeepAliveIntervalNanoseconds))"
        + " minimumHIDOutputMs=\(milliseconds(plan.minimumHIDOutputIntervalNanoseconds))"
        + " recoveryMs=\(milliseconds(recoveryInterval))"
        + " recoveryRounds=\(recoveryRounds)"
        + " livenessMs=\(milliseconds(plan.inputReportLivenessTimeoutNanoseconds))",
    ]
    lines += writes("startup", driver.startupWrites())
    lines += writes("activation", driver.activationWrites())
    lines += writes("keepAlive", driver.keepAliveWrites())
    return lines
  }

  /// The runtime behavior a refactor of the record schema must leave unchanged.
  static func profileLines(_ record: ControllerRecord) -> [String] {
    let profile = record.profile
    let transport = profile.transportProfile
    var lines = [
      "protocol=\(label(profile.physicalProtocolID))"
        + " variant=\(label(profile.physicalProtocolVariant))"
        + " ownership=\(label(profile.ownership))",
      "transport in=\(transport.inputEndpoint) out=\(transport.outputEndpoint)"
        + " interface=\(transport.interfaceNumber) alt=\(transport.alternateSetting)"
        + " interfaceOverride=\(transport.hasInterfaceOverride)"
        + " endpointOverride=\(transport.hasEndpointOverride)"
        + " setConfiguration=\(transport.needsSetConfiguration)"
        + " settleNs=\(transport.postHandshakeSettleNanoseconds)",
      "tuning \(tuning(profile.tuning))",
    ]
    lines += driverLines(record)
    if profile.physicalProtocolID == .xboxGIP {
      let packets = profile.gipStartupPackets.map { hex($0.packet(sequence: 0)) }
      lines.append(
        "gip keepAlive=\(label(profile.gipKeepAlivePolicy))"
          + " startup=[\(packets.joined(separator: ","))]"
      )
    }
    for (index, write) in profile.startupWrites.enumerated() {
      lines.append(
        "recordStartup[\(index)] \(label(write.report.kind)) id=\(write.report.reportID)"
          + " length=\(write.report.length) delayMs=\(write.delayMilliseconds)"
          + " transport=\(label(write.transport)) \(hex(write.bytes))"
      )
    }
    if let template = profile.rumbleTemplate {
      let motors = template.motorBytes.map { "\(label($0.key))@\($0.value)" }.sorted()
      lines.append(
        "rumbleTemplate \(label(template.report.kind)) id=\(template.report.reportID)"
          + " length=\(template.report.length) motors=\(motors.joined(separator: ","))"
      )
    }
    if let layout = profile.inputLayout { lines += layoutLines(layout) }
    if let uuid = profile.bluetoothLEVibrationCharacteristic {
      lines.append("bluetoothLEVibrationCharacteristic \(uuid)")
    }
    // Parameters that only steer report decoding have no resolved value to print here; the
    // parsed frames snapshot covers their effect for the records with sample reports.
    let parameterEntries = profile.parameters.entries + usageLayoutEntries(profile)
    lines.append("parameters=\(parameterEntries.joined(separator: ","))")
    return lines
  }

  /// The snapshot spelled a `hid.descriptor` record's usage map as the `usageLayout` parameter
  /// that selected it. Each name is a record that declares the layout.
  private static let legacyUsageLayouts: [(name: String, vendorID: UInt16, productID: UInt16)] = [
    ("Wr007", 0x11C1, 0x5600), ("ScufEnvision", 0x2E95, 0x434D),
    ("ZRzBrakeLeft", 0x2DC8, 0x301B), ("DragonRise", 0x0079, 0x0006),
  ]

  private static func usageLayoutEntries(_ profile: DeviceRuntimeProfile) -> [String] {
    guard let map = profile.hidUsageMap else { return [] }
    for layout in legacyUsageLayouts {
      let model = ControllerModelID(vendorID: layout.vendorID, productID: layout.productID)
      if ProtocolDriverRegistry().record(for: model)?.hidUsageMap == map {
        return ["usageLayout=\(layout.name)"]
      }
    }
    return ["usageLayout=unknown"]
  }
}
