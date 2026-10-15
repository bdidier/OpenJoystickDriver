import Foundation

/// Per-device transport configuration resolved from controller records.
public struct DeviceTransportProfile: Equatable, Sendable {
  public static let inputEndpointRange = 128...255
  public static let outputEndpointRange = 1...127
  public static let nanosecondsPerMillisecond: UInt64 = 1_000_000

  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8
  public let hasInterfaceOverride: Bool
  public let hasEndpointOverride: Bool
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool
  /// Delay after protocol handshake and before the first IN read.
  public let postHandshakeSettleNanoseconds: UInt64

  public init(
    inputEndpoint: UInt8,
    outputEndpoint: UInt8,
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0,
    hasInterfaceOverride: Bool = false,
    hasEndpointOverride: Bool = false,
    needsSetConfiguration: Bool,
    postHandshakeSettleNanoseconds: UInt64 = 0
  ) {
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.hasInterfaceOverride = hasInterfaceOverride
    self.hasEndpointOverride = hasEndpointOverride
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleNanoseconds = postHandshakeSettleNanoseconds
  }

  public static let gipDefault = Self(
    inputEndpoint: 0x82,
    outputEndpoint: 0x02,
    needsSetConfiguration: false
  )
}

/// A resolved protocol binding: a family and, exactly when the family has variants, the variant
/// in use, written `family[:variant]` (for example `xbox.xusb:receiver`, `xbox.gip:usb` or
/// `vendor.flydigi`).
public struct ProtocolBindingID: Hashable, Sendable, RawRepresentable, Codable,
  CustomStringConvertible
{
  public let protocolID: PhysicalProtocolID
  public let variant: PhysicalProtocolVariantID?

  public init(_ protocolID: PhysicalProtocolID, variant: PhysicalProtocolVariantID? = nil) {
    precondition(
      Self.isValid(protocolID, variant),
      "invalid binding \(protocolID) \(variant as Any)"
    )
    self.protocolID = protocolID
    self.variant = variant
  }

  private static func isValid(
    _ protocolID: PhysicalProtocolID,
    _ variant: PhysicalProtocolVariantID?
  ) -> Bool {
    guard let variant else { return protocolID.variants.isEmpty }
    return protocolID.variants.contains(variant)
  }

  /// Nil unless the text names a family and, optionally, one of its implemented variants.
  public init?(rawValue: String) {
    let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count <= 2, let protocolID = PhysicalProtocolID(rawValue: String(parts[0])) else {
      return nil
    }
    let variant = parts.count == 2 ? PhysicalProtocolVariantID(rawValue: String(parts[1])) : nil
    guard parts.count == 1 || variant != nil, Self.isValid(protocolID, variant) else { return nil }
    self.init(protocolID, variant: variant)
  }

  public var rawValue: String {
    variant.map { "\(protocolID.rawValue):\($0.rawValue)" } ?? protocolID.rawValue
  }

  public var description: String { rawValue }

  /// Whether this binding is reached through raw USB rather than IOHID.
  public var usesRawUSB: Bool { protocolID.usesRawUSB(storedVariant: variant) }
}

/// A driver-owned policy that assembles one logical controller from several protocol roles of
/// one physical device. A catalog row names it in `protocol.assembly`.
///
/// The vocabulary is empty, so validation rejects every name: no catalog row has
/// multi-interface evidence yet, and a selection is stored only with a live producer and
/// consumer. Discovery consumes it through ``ProtocolDriverRegistry/assemblyPolicy(for:)``;
/// until a row adds the first policy, one role is one logical controller.
public enum ControllerAssemblyPolicy: CaseIterable, Hashable, Sendable {
  /// The catalog spelling of this policy.
  public var name: String { switch self {} }

  /// The policy spelled `name`, or nil for a name outside the vocabulary. The vocabulary is
  /// empty, so every name is rejected; the first case adds the lookup over `allCases`.
  init?(name _: String) { return nil }
}

/// Whether the GIP parser sends periodic host-side keep-alive packets.
public enum GIPKeepAlivePolicy: String, Codable, Sendable {
  case enabled
  case disabled
}

/// Who serves a HID controller that macOS also supports as a native gamepad.
public enum ControllerServer: String, Codable, Sendable {
  /// macOS serves it; OJD publishes no virtual controller and sends only the output macOS
  /// leaves undone. A controller macOS does not support is OJD's either way.
  case system
  /// OJD seizes it and publishes its own virtual controller.
  case ojd
}

/// How the record asks OJD to reach the controller; a record without one leaves the route to
/// the family.
public enum ControllerRecordRoute: String, Sendable {
  /// OJD's USB extension claims the controller; the extension matches only the IDs Apple granted.
  case extensionOwned = "ExtensionOwned"
}

/// A record's `tuning` section; each nil field keeps the driver's default.
public struct ControllerTuning: Codable, Equatable, Sendable {
  /// Radial stick deadzone of the output dispatcher, in 0<..<1 of full deflection.
  public let stickDeadzone: Float?
  /// Input silence after which a DualShock 4 session counts as stale.
  public let inputLivenessTimeoutMilliseconds: Int?
  /// Gap between the HID startup writes.
  public let hidStartupIntervalMilliseconds: Int?
  /// Minimum gap between HID output reports.
  public let minimumHIDOutputIntervalMilliseconds: Int?
  /// Gap between the Switch 1 startup recovery rounds.
  public let hidStartupRecoveryIntervalMilliseconds: Int?
  /// Switch 1 startup recovery rounds before the session expires.
  public let hidStartupRecoveryRounds: Int?
  /// Frames that may wait behind a send to the virtual device; a full queue drops its oldest
  /// frame in favor of the newest.
  public let frameQueueCapacity: Int?

  public static let none = Self()

  public init(
    stickDeadzone: Float? = nil,
    inputLivenessTimeoutMilliseconds: Int? = nil,
    hidStartupIntervalMilliseconds: Int? = nil,
    minimumHIDOutputIntervalMilliseconds: Int? = nil,
    hidStartupRecoveryIntervalMilliseconds: Int? = nil,
    hidStartupRecoveryRounds: Int? = nil,
    frameQueueCapacity: Int? = nil
  ) {
    self.stickDeadzone = stickDeadzone
    self.inputLivenessTimeoutMilliseconds = inputLivenessTimeoutMilliseconds
    self.hidStartupIntervalMilliseconds = hidStartupIntervalMilliseconds
    self.minimumHIDOutputIntervalMilliseconds = minimumHIDOutputIntervalMilliseconds
    self.hidStartupRecoveryIntervalMilliseconds = hidStartupRecoveryIntervalMilliseconds
    self.hidStartupRecoveryRounds = hidStartupRecoveryRounds
    self.frameQueueCapacity = frameQueueCapacity
  }
}

/// Complete runtime profile for one physical controller model.
public struct DeviceRuntimeProfile: Equatable, Sendable {
  /// The catalog record's `vvvv-pppp` file stem; nil for a family profile, which has no record.
  public let recordID: String?
  public let transportProfile: DeviceTransportProfile
  public internal(set) var physicalProtocolID: PhysicalProtocolID
  /// Nil when the family has one contract or its variant is a transport variant,
  /// which classification derives from the observed transport.
  public internal(set) var physicalProtocolVariant: PhysicalProtocolVariantID?
  public internal(set) var parameters: ProtocolParameters
  public let capabilityDelta: ControllerCapabilityDelta
  public let preferredBackends: [VirtualControllerBackendID]
  public internal(set) var gipStartupPackets: [GIPStartupPacket]
  public internal(set) var gipKeepAlivePolicy: GIPKeepAlivePolicy
  /// The assembly policy the row names; nil runs each protocol role as its own controller.
  public internal(set) var assemblyPolicy: ControllerAssemblyPolicy?
  public let server: ControllerServer
  /// The record's rumble report, for a driver that encodes rumble from it.
  public let rumbleTemplate: RumbleOutputTemplate?
  /// The record's fixed startup reports, in order; OJD sends them only to a controller it owns.
  public internal(set) var startupWrites: [RecordStartupWrite]
  /// The record's input-report layout; set exactly for the `hid.report-layout` family.
  public let inputLayout: ControllerInputLayout?
  /// The record's HID usage map; set only for a `hid.descriptor` record that declares one.
  var hidUsageMap: HIDUsageMap?
  /// The record's timing and deadzone values; nil fields keep the driver defaults.
  public internal(set) var tuning: ControllerTuning
  /// The record's route; nil leaves it to the family.
  public var route: ControllerRecordRoute?
  /// The record's Bluetooth LE vibration characteristic UUID; set only for Switch 2 controllers.
  public var bluetoothLEVibrationCharacteristic: String?

  /// The interface numbers the selected mode drives; nil binds the one interface the device
  /// exposes.
  public internal(set) var interfaceRange: ClosedRange<UInt8>?

  /// The record's modes other than `default`, in the order their match keys are tried; empty for
  /// most records. The protocol fields above are the default mode's.
  public internal(set) var modes: [ControllerMode] = []
  /// The selected mode's ID; nil while the default mode runs.
  public internal(set) var modeID: String?

  /// Whether this row is reached through raw USB rather than IOHID.
  public var usesRawUSB: Bool {
    physicalProtocolID.usesRawUSB(storedVariant: physicalProtocolVariant)
  }

  /// The binding a raw-USB row resolves to (GIP's only variant is `usb`); nil for IOHID rows,
  /// whose transport variant comes from the observed connection.
  public var rawUSBBinding: ProtocolBindingID? {
    guard usesRawUSB else { return nil }
    return ProtocolBindingID(physicalProtocolID, variant: physicalProtocolVariant ?? .usb)
  }
}
