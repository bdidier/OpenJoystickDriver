/// Normalized controls and sample formats a parser can emit, not a claim of hardware validation.
/// Motion means gyroscope and accelerometer samples in SI units and the canonical controller frame.
public struct ControllerCapabilities: Codable, Hashable, Sendable {
  public let controls: Set<Control>
  /// The triggers (`leftTrigger`, `rightTrigger`) whose press the protocol reports as its own
  /// digital signal. For any other trigger in `controls`, normalization derives the press from the
  /// analog value.
  public let digitalTriggers: Set<Control>
  /// Maximum contacts in one decoded touch frame. Zero means touch decoding is unavailable.
  public let touchContactCount: UInt8
  public let motion: Bool

  public init(
    controls: Set<Control>,
    digitalTriggers: Set<Control> = [],
    touchContactCount: UInt8 = 0,
    motion: Bool = false
  ) {
    self.controls = controls.union(digitalTriggers)
    self.digitalTriggers = digitalTriggers.intersection([.leftTrigger, .rightTrigger])
    self.touchContactCount = touchContactCount
    self.motion = motion
  }

  /// Surface identities emitted by touch samples: one per trackpad, otherwise one primary pad.
  public var touchSurfaces: [ControllerTouchSurface] {
    guard touchContactCount > 0 else { return [] }
    let trackpads = [
      (Control.leftTrackpadTouch, ControllerTouchSurface.left), (.rightTrackpadTouch, .right),
    ].filter { controls.contains($0.0) }.map(\.1)
    return trackpads.isEmpty ? [.primary] : trackpads
  }

  public func intersecting(_ other: Self) -> Self {
    Self(
      controls: controls.intersection(other.controls),
      digitalTriggers: digitalTriggers.intersection(other.digitalTriggers),
      touchContactCount: min(touchContactCount, other.touchContactCount),
      motion: motion && other.motion
    )
  }

  public func union(_ other: Self) -> Self {
    Self(
      controls: controls.union(other.controls),
      digitalTriggers: digitalTriggers.union(other.digitalTriggers),
      touchContactCount: max(touchContactCount, other.touchContactCount),
      motion: motion || other.motion
    )
  }

  private enum CodingKeys: String, CodingKey {
    case controls, digitalTriggers, touchContactCount, motion
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      controls: try container.decode(Set<Control>.self, forKey: .controls),
      digitalTriggers: try container.decodeIfPresent(Set<Control>.self, forKey: .digitalTriggers)
        ?? [],
      touchContactCount: try container.decode(UInt8.self, forKey: .touchContactCount),
      motion: try container.decode(Bool.self, forKey: .motion)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Control.allCases.filter(controls.contains), forKey: .controls)
    if !digitalTriggers.isEmpty {
      try container.encode(
        Control.allCases.filter(digitalTriggers.contains),
        forKey: .digitalTriggers
      )
    }
    try container.encode(touchContactCount, forKey: .touchContactCount)
    try container.encode(motion, forKey: .motion)
  }
}

/// Evidenced capability corrections a catalog row applies to its parser's declared defaults.
public struct ControllerCapabilityDelta: Equatable, Sendable {
  public static let none = Self(absentControls: [], presentControls: [], rumbleAbsent: false)

  /// Declared controls this model does not have.
  public let absentControls: Set<Control>
  /// Controls this model adds to its family defaults; the driver emits them only when selected.
  public let presentControls: Set<Control>
  /// The model has no rumble channel.
  public let rumbleAbsent: Bool

  public init(absentControls: Set<Control>, presentControls: Set<Control>, rumbleAbsent: Bool) {
    self.absentControls = absentControls
    self.presentControls = presentControls
    self.rumbleAbsent = rumbleAbsent
  }
}
