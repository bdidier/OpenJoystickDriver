import Foundation

extension ControllerTuning {
  /// One tuning value, named as in a record's and `all.patch.json`'s `tuning` section. The cases
  /// are in the order `validateTuning` reports a family-scope violation.
  public enum Key: String, CaseIterable, Sendable {
    case stickDeadzone
    case inputLivenessTimeoutMs
    case hidStartupRecoveryIntervalMs
    case hidStartupRecoveryRounds
    case hidStartupIntervalMs
    case minimumHIDOutputIntervalMs
  }

  /// The keys this tuning sets.
  public var setKeys: Set<Key> { Set(Key.allCases.filter { text(of: $0) != nil }) }

  /// The value of `key` as the JSON number it is written as; nil when unset.
  public func text(of key: Key) -> String? {
    switch key {
    case .stickDeadzone: stickDeadzone.map { "\($0)" }
    case .inputLivenessTimeoutMs: inputLivenessTimeoutMilliseconds.map(String.init)
    case .hidStartupRecoveryIntervalMs: hidStartupRecoveryIntervalMilliseconds.map(String.init)
    case .hidStartupRecoveryRounds: hidStartupRecoveryRounds.map(String.init)
    case .hidStartupIntervalMs: hidStartupIntervalMilliseconds.map(String.init)
    case .minimumHIDOutputIntervalMs: minimumHIDOutputIntervalMilliseconds.map(String.init)
    }
  }

  /// This tuning with every key `higher` sets replaced by `higher`'s value.
  public func overlaid(by higher: Self) -> Self {
    Self(
      stickDeadzone: higher.stickDeadzone ?? stickDeadzone,
      inputLivenessTimeoutMilliseconds: higher.inputLivenessTimeoutMilliseconds
        ?? inputLivenessTimeoutMilliseconds,
      hidStartupIntervalMilliseconds: higher.hidStartupIntervalMilliseconds
        ?? hidStartupIntervalMilliseconds,
      minimumHIDOutputIntervalMilliseconds: higher.minimumHIDOutputIntervalMilliseconds
        ?? minimumHIDOutputIntervalMilliseconds,
      hidStartupRecoveryIntervalMilliseconds: higher.hidStartupRecoveryIntervalMilliseconds
        ?? hidStartupRecoveryIntervalMilliseconds,
      hidStartupRecoveryRounds: higher.hidStartupRecoveryRounds ?? hidStartupRecoveryRounds
    )
  }

  /// This tuning without the keys outside `keys`.
  func keeping(_ keys: Set<Key>) -> Self {
    Self(
      stickDeadzone: keys.contains(.stickDeadzone) ? stickDeadzone : nil,
      inputLivenessTimeoutMilliseconds: keys.contains(.inputLivenessTimeoutMs)
        ? inputLivenessTimeoutMilliseconds : nil,
      hidStartupIntervalMilliseconds: keys.contains(.hidStartupIntervalMs)
        ? hidStartupIntervalMilliseconds : nil,
      minimumHIDOutputIntervalMilliseconds: keys.contains(.minimumHIDOutputIntervalMs)
        ? minimumHIDOutputIntervalMilliseconds : nil,
      hidStartupRecoveryIntervalMilliseconds: keys.contains(.hidStartupRecoveryIntervalMs)
        ? hidStartupRecoveryIntervalMilliseconds : nil,
      hidStartupRecoveryRounds: keys.contains(.hidStartupRecoveryRounds)
        ? hidStartupRecoveryRounds : nil
    )
  }
}

extension ControllerRecord {
  /// Whether this controller's driver reads `key`; `all.patch.json` sets it only where this holds.
  public func reads(_ key: ControllerTuning.Key) -> Bool { tuningScope.contains(key) }
}

extension ControllerTuning {
  /// Why `key` does not apply to a controller of this family and stored variant, or nil when a
  /// driver reads it. A nil `protocolID` is a record with no known family: it reads only
  /// `stickDeadzone`. `Scripts/Catalog/controller_patch.py` implements the same rule.
  static func scopeViolation(
    _ key: Key,
    protocolID: PhysicalProtocolID?,
    variant: PhysicalProtocolVariantID?
  ) -> String? {
    switch key {
    case .stickDeadzone: return nil
    case .inputLivenessTimeoutMs:
      return protocolID == .sonyDualShock4
        ? nil : "inputLivenessTimeoutMs requires the sony.dualshock4 family"
    case .hidStartupRecoveryIntervalMs, .hidStartupRecoveryRounds:
      return protocolID == .nintendoSwitch1
        ? nil : "startup recovery tuning requires a Switch 1 controller with startup recovery"
    case .hidStartupIntervalMs, .minimumHIDOutputIntervalMs:
      guard let protocolID else { return "HID startup and output timings need a known family" }
      return protocolID.usesRawUSB(storedVariant: variant)
        ? "HID startup and output timings apply only to HID controllers" : nil
    }
  }

  /// The keys that a controller of the record `document` reads, from its `protocol` family and
  /// variant.
  static func scope(ofDocument document: [String: Any]) -> Set<Key> {
    let info = document["protocol"] as? [String: Any]
    let protocolID = (info?["family"] as? String).flatMap(PhysicalProtocolID.init(rawValue:))
    let variant = (info?["variant"] as? String).flatMap(PhysicalProtocolVariantID.init(rawValue:))
    return Set(
      Key.allCases.filter {
        scopeViolation($0, protocolID: protocolID, variant: variant) == nil
      }
    )
  }
}

extension ControllerRecordDocument {
  /// Why `key` does not apply to this record's family, or nil when a driver reads it.
  func tuningScopeViolation(_ key: ControllerTuning.Key) -> String? {
    ControllerTuning.scopeViolation(
      key,
      protocolID: protocolInfo.protocolID,
      variant: protocolInfo.protocolVariant
    )
  }
}
