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
    case keepAliveIntervalMs
    case lizardResendTicks
    case usbCommandTimeoutMs
    case presenceResendReports
    case adapterDisconnectDelayMs
    case usbStartupIntervalMs
    case usbStartupRetryDelayMs
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
    case .keepAliveIntervalMs: keepAliveIntervalMilliseconds.map(String.init)
    case .lizardResendTicks: lizardResendTicks.map(String.init)
    case .usbCommandTimeoutMs: usbCommandTimeoutMilliseconds.map(String.init)
    case .presenceResendReports: presenceResendReports.map(String.init)
    case .adapterDisconnectDelayMs: adapterDisconnectDelayMilliseconds.map(String.init)
    case .usbStartupIntervalMs: usbStartupIntervalMilliseconds.map(String.init)
    case .usbStartupRetryDelayMs: usbStartupRetryDelayMilliseconds.map(String.init)
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
      hidStartupRecoveryRounds: higher.hidStartupRecoveryRounds ?? hidStartupRecoveryRounds,
      keepAliveIntervalMilliseconds: higher.keepAliveIntervalMilliseconds
        ?? keepAliveIntervalMilliseconds,
      lizardResendTicks: higher.lizardResendTicks ?? lizardResendTicks,
      usbCommandTimeoutMilliseconds: higher.usbCommandTimeoutMilliseconds
        ?? usbCommandTimeoutMilliseconds,
      presenceResendReports: higher.presenceResendReports ?? presenceResendReports,
      adapterDisconnectDelayMilliseconds: higher.adapterDisconnectDelayMilliseconds
        ?? adapterDisconnectDelayMilliseconds,
      usbStartupIntervalMilliseconds: higher.usbStartupIntervalMilliseconds
        ?? usbStartupIntervalMilliseconds,
      usbStartupRetryDelayMilliseconds: higher.usbStartupRetryDelayMilliseconds
        ?? usbStartupRetryDelayMilliseconds
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
        ? hidStartupRecoveryRounds : nil,
      keepAliveIntervalMilliseconds: keys.contains(.keepAliveIntervalMs)
        ? keepAliveIntervalMilliseconds : nil,
      lizardResendTicks: keys.contains(.lizardResendTicks) ? lizardResendTicks : nil,
      usbCommandTimeoutMilliseconds: keys.contains(.usbCommandTimeoutMs)
        ? usbCommandTimeoutMilliseconds : nil,
      presenceResendReports: keys.contains(.presenceResendReports) ? presenceResendReports : nil,
      adapterDisconnectDelayMilliseconds: keys.contains(.adapterDisconnectDelayMs)
        ? adapterDisconnectDelayMilliseconds : nil,
      usbStartupIntervalMilliseconds: keys.contains(.usbStartupIntervalMs)
        ? usbStartupIntervalMilliseconds : nil,
      usbStartupRetryDelayMilliseconds: keys.contains(.usbStartupRetryDelayMs)
        ? usbStartupRetryDelayMilliseconds : nil
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
  /// `stickDeadzone`. The family's description holds the keys; `controller_patch.py`
  /// reads the same description.
  static func scopeViolation(
    _ key: Key,
    protocolID: PhysicalProtocolID?,
    variant: PhysicalProtocolVariantID?
  ) -> String? {
    guard !scope(protocolID: protocolID, variant: variant).contains(key) else { return nil }
    return "\(key.rawValue) is not read by the \(protocolID?.rawValue ?? "unknown") driver"
  }

  /// The keys that a controller of this family and stored variant reads.
  static func scope(
    protocolID: PhysicalProtocolID?,
    variant: PhysicalProtocolVariantID?
  ) -> Set<Key> {
    guard let description = protocolID?.protocolDescription else { return [.stickDeadzone] }
    return description.tuningScope(variant: variant)
  }

  /// The keys that a controller of the record `document` reads, from its `protocol` family and
  /// variant.
  static func scope(ofDocument document: [String: Any]) -> Set<Key> {
    let info = document["protocol"] as? [String: Any]
    let protocolID = (info?["family"] as? String).flatMap(PhysicalProtocolID.init(rawValue:))
    let variant = (info?["variant"] as? String).flatMap(PhysicalProtocolVariantID.init(rawValue:))
    return scope(protocolID: protocolID, variant: variant)
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
