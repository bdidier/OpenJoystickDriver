import Foundation

/// An unsigned control value; `0` is released/minimum and `65535` is fully actuated.
public struct UnipolarValue: Hashable, Codable, Sendable {
  public static let min = Self(0)
  public static let max = Self(UInt16.max)

  public let rawValue: UInt16

  public init(_ rawValue: UInt16) { self.rawValue = rawValue }

  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(UInt16.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A signed control value centered on `0`, with symmetric magnitude `-32767...32767`.
public struct BipolarValue: Hashable, Codable, Sendable {
  public static let min = Self(-Int16.max)
  public static let center = Self(0)
  public static let max = Self(Int16.max)

  public let rawValue: Int16

  /// Clamps a raw `-32768` to `-32767` so both directions have the same magnitude.
  public init(_ rawValue: Int16) { self.rawValue = Swift.max(rawValue, -Int16.max) }

  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(Int16.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Nanoseconds from one process-local monotonic clock.
public struct MonotonicTimestamp: Hashable, Comparable, Codable, Sendable {
  public let nanoseconds: UInt64

  public init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
}

/// The one control vocabulary: position-based ids that physical labels never rename.
///
/// The raw value is the UpperCamelCase id the schemas, records, profiles and the endpoint use.
/// `Resources/Schemas/vocabulary.schema.json` `$defs/control` defines the same set; a test keeps
/// the two equal. A press of a trigger is the `leftTrigger` or `rightTrigger` id, and the D-pad is
/// four ids rather than one hat.
public enum Control: String, CaseIterable, Codable, Sendable {
  case south = "South"
  case east = "East"
  case west = "West"
  case north = "North"
  case leftShoulder = "LeftShoulder"
  case rightShoulder = "RightShoulder"
  case leftTrigger = "LeftTrigger"
  case rightTrigger = "RightTrigger"
  case back = "Back"
  case start = "Start"
  case leftStickClick = "LeftStickClick"
  case rightStickClick = "RightStickClick"
  case dpadUp = "DpadUp"
  case dpadDown = "DpadDown"
  case dpadLeft = "DpadLeft"
  case dpadRight = "DpadRight"
  case guide = "Guide"
  case capture = "Capture"
  case microphone = "Microphone"
  case touchpadClick = "TouchpadClick"
  case leftPaddle1 = "LeftPaddle1"
  case leftPaddle2 = "LeftPaddle2"
  case rightPaddle1 = "RightPaddle1"
  case rightPaddle2 = "RightPaddle2"
  case auxiliary1 = "Auxiliary1"
  case auxiliary2 = "Auxiliary2"
  case auxiliary3 = "Auxiliary3"
  case auxiliary4 = "Auxiliary4"
  case auxiliary5 = "Auxiliary5"
  case auxiliary6 = "Auxiliary6"
  case auxiliary7 = "Auxiliary7"
  case auxiliary8 = "Auxiliary8"
  case leftStickX = "LeftStickX"
  case leftStickY = "LeftStickY"
  case rightStickX = "RightStickX"
  case rightStickY = "RightStickY"
  case leftStickTouch = "LeftStickTouch"
  case rightStickTouch = "RightStickTouch"
  case leftTrackpadClick = "LeftTrackpadClick"
  case rightTrackpadClick = "RightTrackpadClick"
  case leftTrackpadTouch = "LeftTrackpadTouch"
  case rightTrackpadTouch = "RightTrackpadTouch"

  /// The four D-pad ids; a controller with a D-pad or hat has all of them.
  public static let dpad: Set<Control> = [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]

  /// The four stick axes.
  public static let stickAxes: [Self] = [.leftStickX, .leftStickY, .rightStickX, .rightStickY]

  /// Controls of the standard Xbox layout, excluding `guide`.
  public static let xboxLayout: Set<Control> = dpad.union([
    .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftStickClick, .rightStickClick,
    .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
    .back, .start,
  ])

  /// Whether the virtual gamepad report has a button for this control. A paddle, an auxiliary
  /// button, a trackpad and a stick touch have none.
  public var supportsVirtualOutput: Bool {
    switch self {
    case .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
      .back, .start, .leftStickClick, .rightStickClick, .guide, .capture, .dpadUp, .dpadDown,
      .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .rightStickX, .rightStickY:
      return true
    case .microphone, .touchpadClick, .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2,
      .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7,
      .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick, .rightTrackpadClick,
      .leftTrackpadTouch, .rightTrackpadTouch:
      return false
    }
  }
}

/// One of eight compass directions, or neutral (center) for a hat or D-pad.
public enum HatDirection: String, Codable, Sendable {
  case neutral = "Neutral"
  case north = "North"
  case northEast = "NorthEast"
  case east = "East"
  case southEast = "SouthEast"
  case south = "South"
  case southWest = "SouthWest"
  case west = "West"
  case northWest = "NorthWest"
}

extension HatDirection {
  /// The D-pad control the hat points at; a diagonal names its vertical id, and neutral the
  /// first D-pad id.
  public var dpadControl: Control {
    switch self {
    case .north, .northEast, .northWest, .neutral: .dpadUp
    case .south, .southEast, .southWest: .dpadDown
    case .east: .dpadRight
    case .west: .dpadLeft
    }
  }
}

/// Battery charge at the precision the device reports, never a synthesized midpoint.
public struct BatteryLevel: Codable, Hashable, Sendable {
  public static let unknown = Self(percentage: nil)

  /// Charge within `0...100`: one value for an exact reading, the device's bucket otherwise, and
  /// `nil` when the device reports no level.
  public let percentage: ClosedRange<UInt8>?

  public init(percentage: ClosedRange<UInt8>?) {
    precondition(percentage.map { $0.upperBound <= 100 } ?? true, "Battery charge exceeds 100%")
    self.percentage = percentage
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let percentage = try container.decodeIfPresent(ClosedRange<UInt8>.self, forKey: .percentage)
    guard percentage.map({ $0.upperBound <= 100 }) ?? true else {
      throw DecodingError.dataCorruptedError(
        forKey: .percentage,
        in: container,
        debugDescription: "Battery charge exceeds 100%"
      )
    }
    self.percentage = percentage
  }

  /// Locale-independent ASCII charge, `73%` or `0-9%`; `nil` when unknown.
  public var percentageText: String? {
    guard let percentage else { return nil }
    if percentage.lowerBound == percentage.upperBound { return "\(percentage.lowerBound)%" }
    return "\(percentage.lowerBound)-\(percentage.upperBound)%"
  }
}

/// Link and power state of one logical controller.
public struct ControllerConnectionState: Codable, Equatable, Sendable {
  public enum Charging: String, Codable, Sendable {
    case unknown
    case discharging
    case charging
    case full
    case notChargeable
  }

  /// Power facts a driver decodes from its own reports.
  public struct Power: Codable, Equatable, Sendable {
    public static let unknown = Self(charging: .unknown, battery: .unknown, wiredPower: nil)

    public let charging: Charging
    public let battery: BatteryLevel
    /// Whether wired power is available; `nil` when the device does not report it.
    public let wiredPower: Bool?

    public init(charging: Charging, battery: BatteryLevel, wiredPower: Bool?) {
      self.charging = charging
      self.battery = battery
      self.wiredPower = wiredPower
    }
  }

  /// Controller-side link; `nil` without evidence. Wireless is never inferred from absent USB.
  public let transport: PhysicalTransport?
  public let backend: DeviceAccessBackend
  /// Whether the controller is linked; a `proprietary-radio-receiver` slot can be empty.
  public let isConnected: Bool
  public let power: Power

  public init(
    transport: PhysicalTransport?,
    backend: DeviceAccessBackend,
    isConnected: Bool,
    power: Power
  ) {
    self.transport = transport
    self.backend = backend
    self.isConnected = isConnected
    self.power = power
  }
}
