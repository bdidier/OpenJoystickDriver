import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverUSB

/// Snapshots the behavior the bundled catalog drives today: each record's runtime profile and
/// the route that reaches its controller.
struct EquivalenceSnapshotCatalogTests {
  private static let records = ControllerRecordSet.bundled.records.values.sorted {
    ($0.identity.vendorID, $0.identity.productID) < ($1.identity.vendorID, $1.identity.productID)
  }

  private static func title(_ record: ControllerRecord) -> String {
    EquivalenceSnapshotStore.recordTitle(
      vendorID: record.identity.vendorID,
      productID: record.identity.productID
    )
  }

  /// A value's description without module names, so the text does not name the build.
  private static func plain(_ value: Any) -> String {
    "\(value)".replacingOccurrences(of: "OpenJoystickDriverKit.", with: "")
  }

  /// The tuning keys the record sets, in declaration order.
  private static func tuning(_ tuning: ControllerTuning) -> String {
    let set = Mirror(reflecting: tuning).children.compactMap { child -> String? in
      guard let label = child.label, let wrapped = Mirror(reflecting: child.value).children.first
      else { return nil }
      return "\(label):\(wrapped.value)"
    }
    return set.isEmpty ? "-" : set.joined(separator: ",")
  }

  /// The runtime fields a refactor of the record schema must leave unchanged.
  private static func profileLines(_ record: ControllerRecord) -> [String] {
    let profile = record.profile
    let transport = profile.transportProfile
    let delta = profile.capabilityDelta
    func controls(_ set: Set<ControlID>) -> String {
      set.map(\.rawValue).sorted().joined(separator: ",")
    }
    var lines = [
      "family=\(record.family) protocol=\(profile.physicalProtocolID.rawValue)"
        + " variant=\(profile.physicalProtocolVariant?.rawValue ?? "-")"
        + " ownership=\(profile.ownership.rawValue)",
      "quirks=\(profile.quirks.map(\.rawValue).sorted().joined(separator: ","))",
      "transport in=\(transport.inputEndpoint) out=\(transport.outputEndpoint)"
        + " interface=\(transport.interfaceNumber) alt=\(transport.alternateSetting)"
        + " interfaceOverride=\(transport.hasInterfaceOverride)"
        + " endpointOverride=\(transport.hasEndpointOverride)"
        + " setConfiguration=\(transport.needsSetConfiguration)"
        + " settleNs=\(transport.postHandshakeSettleNanoseconds)",
      "capabilities absent=[\(controls(delta.absentControls))]"
        + " present=[\(controls(delta.presentControls))] rumbleAbsent=\(delta.rumbleAbsent)",
      "gipKeepAlive=\(profile.gipKeepAlivePolicy.rawValue)"
        + " assembly=\(profile.assemblyPolicy.map { "\($0)" } ?? "-")"
        + " backends=\(profile.preferredBackends.map { "\($0)" }.joined(separator: ","))",
      "tuning=\(tuning(profile.tuning))",
      "gipStartupPackets=\(plain(profile.gipStartupPackets))",
    ]
    if !profile.startupWrites.isEmpty {
      lines.append("startupWrites=\(plain(profile.startupWrites))")
    }
    if let template = profile.rumbleTemplate {
      let motors = template.motorBytes.map { "\($0.key.rawValue):\($0.value)" }.sorted()
      lines.append(
        "rumbleTemplate=\(plain(template.report)) motors=\(motors.joined(separator: ","))"
      )
    }
    if let layout = profile.inputLayout { lines.append("inputLayout=\(plain(layout))") }
    if let uuid = profile.bluetoothLEVibrationCharacteristic {
      lines.append("bluetoothLEVibrationCharacteristic=\(uuid)")
    }
    return lines
  }

  /// How the controller is reached today: the signed USB extension for the Microsoft products
  /// Apple approved, IOUSBHost raw access for other raw-USB records, and the system HID stack
  /// otherwise.
  private static func route(_ record: ControllerRecord) -> String {
    guard record.usesRawUSB else { return "system ownership=\(record.ownership.rawValue)" }
    let claimed =
      record.identity.vendorID == USBDriverKitExtensionConfiguration.microsoftVendorID
      && USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(record.identity.productID)
    return claimed ? "extension" : "raw-access"
  }

  @Test
  func catalogIndexMatchesSnapshot() throws {
    let sections = Self.records.map { (title: Self.title($0), lines: Self.profileLines($0)) }
    let rendered = EquivalenceSnapshotStore.render(sections)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "catalog-index.txt") == nil)
  }

  @Test
  func recordRoutesMatchSnapshot() throws {
    let sections = Self.records.map { (title: Self.title($0), lines: [Self.route($0)]) }
    let rendered = EquivalenceSnapshotStore.render(sections)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "record-routes.txt") == nil)
  }
}
