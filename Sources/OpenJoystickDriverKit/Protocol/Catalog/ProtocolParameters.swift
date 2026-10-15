import Foundation

/// The typed, family-scoped values of a controller record's `protocol.parameters`.
///
/// Each field is declared by the protocol drivers named beside it; ``violation(family:variant:)``
/// rejects a field outside its driver. A parameter changes how the driver decodes or reaches a
/// variant; one that decodes a fixed extra button bit also declares that control. Capability
/// corrections are ``ControllerCapabilityDelta``. An absent field keeps the driver's default, so
/// a record never spells a default value.
public struct ProtocolParameters: Codable, Equatable, Sendable {
  /// Where a GIP packet carries the Share button, counted back from the packet's end (Linux
  /// xpad `MAP_SHARE_OFFSET`). `xbox.gip`.
  public struct ShareButton: Codable, Equatable, Sendable {
    public let fromEnd: Int

    public init(fromEnd: Int) { self.fromEnd = fromEnd }

    /// The packet-end offsets a record may name.
    static let fromEndRange = 1...255

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["fromEnd"])
      fromEnd = try container.decode(Int.self, for: "fromEnd")
      guard Self.fromEndRange.contains(fromEnd) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("fromEnd")],
            debugDescription: "fromEnd must be in \(Self.fromEndRange)"
          )
        )
      }
    }
  }

  /// The axis and button permutation of a Nintendo controller. `nintendo.switch1` takes `Pro`,
  /// `JoyConLeft` and `JoyConRight`; `nintendo.switch2` also takes `GameCube`, the NSO GameCube
  /// controller with analog triggers and flash trigger calibration. On `nintendo.switch2` the
  /// Joy-Con values select the Joy-Con 2 layout.
  public enum Layout: String, Codable, CaseIterable, Sendable {
    case pro = "Pro"
    case joyConLeft = "JoyConLeft"
    case joyConRight = "JoyConRight"
    case gameCube = "GameCube"
  }

  /// What a Switch pad's USB link does. `ChargingOnly` is a pad that enumerates over USB for
  /// charging but speaks the protocol only over Bluetooth (SDL
  /// `HIDAPI_DriverSwitch_IsSupportedDevice`, Linux `hid-nintendo.c` device table).
  /// `nintendo.switch1`.
  public enum USBProtocol: String, Codable, CaseIterable, Sendable {
    case chargingOnly = "ChargingOnly"
  }

  /// How GameSir enhanced HID lighting memory is organized. `ProfileSlots`: the driver reads the
  /// active slot at startup, tracks it, and writes color and brightness into that slot.
  /// `vendor.gamesir` enhanced HID.
  public enum LightingMemory: String, Codable, CaseIterable, Sendable {
    case profileSlots = "ProfileSlots"
  }

  /// Where a third-party PS3 pad's hat comes from. `DpadPressure`: its hat bits are untrusted, so
  /// any nonzero D-pad pressure byte holds its direction (SDL `SDL_hidapi_ps3.c`, Saitek Cyborg
  /// V.3 Rumble Pad). `vendor.ps3-third-party`.
  public enum HatSource: String, Codable, CaseIterable, Sendable {
    case dpadPressure = "DpadPressure"
  }

  /// Which motion calibration report a DualShock 4 trusts. `Factory`: the report is trusted. SDL
  /// `SDL_hidapi_ps4.c` reads it only on Sony's own controllers; other pads keep the nominal
  /// scale. `sony.dualshock4`.
  public enum MotionCalibration: String, Codable, CaseIterable, Sendable {
    case factory = "Factory"
  }

  /// The part a Sony device plays. `WirelessAdapter` (`sony.dualshock4`) is Sony's DualShock 4
  /// wireless adapter (SDL `USB_PRODUCT_SONY_DS4_DONGLE`): output waits for a paired pad, and its
  /// calibration uses the Bluetooth gyro order. `Receiver` (`sony.dualsense`) is a third-party
  /// wireless receiver that keeps reporting with no controller paired.
  public enum Role: String, Codable, CaseIterable, Sendable {
    case wirelessAdapter = "WirelessAdapter"
    case receiver = "Receiver"
  }

  /// The motion scale of a DualShock 4 model. `StrikePad` is the STRIKEPAD grip (SDL
  /// `USB_PRODUCT_SONY_DS4_STRIKEPAD`): doubled gyro scale and doubled, negated accelerometer
  /// scale. `sony.dualshock4`.
  public enum MotionScale: String, Codable, CaseIterable, Sendable {
    case strikePad = "StrikePad"
  }

  /// The input report revision of an NVIDIA SHIELD controller. `Shield2015` is the 2015
  /// controller (SDL `SDL_hidapi_shield.c` V103): plain rumble output report and a touchpad
  /// click; without it the driver runs the input-only 2017 controller. `vendor.nvidia-shield`.
  public enum ReportRevision: String, Codable, CaseIterable, Sendable {
    case shield2015 = "Shield2015"
  }

  /// The usage layout of a `hid.descriptor` pad whose descriptor is not enough to choose it.
  public enum UsageLayout: String, Codable, CaseIterable, Sendable {
    /// Z/Rz right stick, Accelerator as LT and Brake as RT, and the WR007 button order.
    case wr007 = "Wr007"
    /// Input only from report 6, buttons 1-10, and Z/Rz swapped with Rx/Ry.
    case scufEnvision = "ScufEnvision"
    /// WR007's Z/Rz right stick and button order, with Brake as LT and a Home button. Records
    /// name it for pads whose descriptor is not recorded; a descriptor of this shape selects it
    /// anyway.
    case zRzBrakeLeft = "ZRzBrakeLeft"
    /// DragonRise generic USB PCB: Z/Rz right stick and DirectInput button order, where 1-4 are
    /// Y, B, A, X and 7-8 are digital L2 and R2.
    case dragonRise = "DragonRise"
  }

  /// Who made a DualSense-protocol controller. `ThirdParty` is one that Sony did not make: the
  /// driver follows SDL's non-Sony path, probing for features. The other `sony.dualsense`
  /// fields describe a third-party DualSense and need this one.
  public enum Maker: String, Codable, CaseIterable, Sendable {
    case thirdParty = "ThirdParty"
  }

  public var shareButton: ShareButton?
  public var layout: Layout?
  public var usbProtocol: USBProtocol?
  /// GameSir enhanced HID reports the inner grips in extras-byte bits 0x40 and 0x80.
  public var innerGrips: Bool?
  public var lightingMemory: LightingMemory?
  public var hatSource: HatSource?
  public var motionCalibration: MotionCalibration?
  public var role: Role?
  public var motionScale: MotionScale?
  public var reportRevision: ReportRevision?
  public var usageLayout: UsageLayout?
  public var maker: Maker?
  /// Third-party DualSense with sensors though it does not answer the probe (SDL's Razer list).
  public var unprobedSensors: Bool?
  /// Third-party DualSense with a touchpad though it does not answer the probe (SDL's Razer
  /// list). Either unprobed field also selects the alternate report without a probe reply.
  public var unprobedTouchpad: Bool?
  /// Third-party DualSense whose probe reply omits the vibration it has (SDL's NACON entry).
  public var forcedVibration: Bool?

  /// A record that names no parameter.
  public static let none = Self()

  public init(
    shareButton: ShareButton? = nil,
    layout: Layout? = nil,
    usbProtocol: USBProtocol? = nil,
    innerGrips: Bool? = nil,
    lightingMemory: LightingMemory? = nil,
    hatSource: HatSource? = nil,
    motionCalibration: MotionCalibration? = nil,
    role: Role? = nil,
    motionScale: MotionScale? = nil,
    reportRevision: ReportRevision? = nil,
    usageLayout: UsageLayout? = nil,
    maker: Maker? = nil,
    unprobedSensors: Bool? = nil,
    unprobedTouchpad: Bool? = nil,
    forcedVibration: Bool? = nil
  ) {
    self.shareButton = shareButton
    self.layout = layout
    self.usbProtocol = usbProtocol
    self.innerGrips = innerGrips
    self.lightingMemory = lightingMemory
    self.hatSource = hatSource
    self.motionCalibration = motionCalibration
    self.role = role
    self.motionScale = motionScale
    self.reportRevision = reportRevision
    self.usageLayout = usageLayout
    self.maker = maker
    self.unprobedSensors = unprobedSensors
    self.unprobedTouchpad = unprobedTouchpad
    self.forcedVibration = forcedVibration
  }

  /// Every parameter name a record may write.
  static let names: Set<String> = [
    "shareButton", "layout", "usbProtocol", "innerGrips", "lightingMemory", "hatSource",
    "motionCalibration", "role", "motionScale", "reportRevision", "usageLayout", "maker",
    "unprobedSensors", "unprobedTouchpad", "forcedVibration",
  ]

  /// Strictly decodes the object: an unknown name or a value of the wrong type fails, and a
  /// flag is `true` or absent.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: Self.names)
    guard !container.allKeys.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "parameters must not be empty")
      )
    }
    func flag(_ name: String) throws -> Bool? {
      guard let value = try container.decodeOptional(Bool.self, for: name) else { return nil }
      guard value else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey(name)],
            debugDescription: "\(name) is true or omitted"
          )
        )
      }
      return true
    }
    shareButton = try container.decodeOptional(ShareButton.self, for: "shareButton")
    layout = try container.decodeOptional(Layout.self, for: "layout")
    usbProtocol = try container.decodeOptional(USBProtocol.self, for: "usbProtocol")
    innerGrips = try flag("innerGrips")
    lightingMemory = try container.decodeOptional(LightingMemory.self, for: "lightingMemory")
    hatSource = try container.decodeOptional(HatSource.self, for: "hatSource")
    motionCalibration = try container.decodeOptional(
      MotionCalibration.self,
      for: "motionCalibration"
    )
    role = try container.decodeOptional(Role.self, for: "role")
    motionScale = try container.decodeOptional(MotionScale.self, for: "motionScale")
    reportRevision = try container.decodeOptional(ReportRevision.self, for: "reportRevision")
    usageLayout = try container.decodeOptional(UsageLayout.self, for: "usageLayout")
    maker = try container.decodeOptional(Maker.self, for: "maker")
    unprobedSensors = try flag("unprobedSensors")
    unprobedTouchpad = try flag("unprobedTouchpad")
    forcedVibration = try flag("forcedVibration")
  }

  /// The set parameters as sorted `name=value` entries; empty when the record names none.
  public var entries: [String] {
    var result: [String] = []
    if let shareButton { result.append("shareButton.fromEnd=\(shareButton.fromEnd)") }
    if let layout { result.append("layout=\(layout.rawValue)") }
    if let usbProtocol { result.append("usbProtocol=\(usbProtocol.rawValue)") }
    if innerGrips != nil { result.append("innerGrips=true") }
    if let lightingMemory { result.append("lightingMemory=\(lightingMemory.rawValue)") }
    if let hatSource { result.append("hatSource=\(hatSource.rawValue)") }
    if let motionCalibration { result.append("motionCalibration=\(motionCalibration.rawValue)") }
    if let role { result.append("role=\(role.rawValue)") }
    if let motionScale { result.append("motionScale=\(motionScale.rawValue)") }
    if let reportRevision { result.append("reportRevision=\(reportRevision.rawValue)") }
    if let usageLayout { result.append("usageLayout=\(usageLayout.rawValue)") }
    if let maker { result.append("maker=\(maker.rawValue)") }
    if unprobedSensors != nil { result.append("unprobedSensors=true") }
    if unprobedTouchpad != nil { result.append("unprobedTouchpad=true") }
    if forcedVibration != nil { result.append("forcedVibration=true") }
    return result.sorted()
  }

  /// One line for CLI and log output: the entries joined by commas, or `none`.
  public var summary: String { entries.isEmpty ? "none" : entries.joined(separator: ",") }

  public var isEmpty: Bool { entries.isEmpty }

  /// The names of the set parameters.
  private var setNames: Set<String> {
    var result: Set<String> = []
    if shareButton != nil { result.insert("shareButton") }
    if layout != nil { result.insert("layout") }
    if usbProtocol != nil { result.insert("usbProtocol") }
    if innerGrips != nil { result.insert("innerGrips") }
    if lightingMemory != nil { result.insert("lightingMemory") }
    if hatSource != nil { result.insert("hatSource") }
    if motionCalibration != nil { result.insert("motionCalibration") }
    if role != nil { result.insert("role") }
    if motionScale != nil { result.insert("motionScale") }
    if reportRevision != nil { result.insert("reportRevision") }
    if usageLayout != nil { result.insert("usageLayout") }
    if maker != nil { result.insert("maker") }
    if unprobedSensors != nil { result.insert("unprobedSensors") }
    if unprobedTouchpad != nil { result.insert("unprobedTouchpad") }
    if forcedVibration != nil { result.insert("forcedVibration") }
    return result
  }

  /// The parameter names the family's protocol description declares.
  static func declared(by family: PhysicalProtocolID) -> Set<String> {
    ProtocolDescription.bundled[family].map { Set($0.parameters.keys) } ?? []
  }

  /// Why the parameters cannot belong to `family`, or nil when its driver declares them all and
  /// they agree with one another.
  func violation(
    family: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?
  ) -> String? {
    guard setNames.isSubset(of: Self.declared(by: family)) else {
      return "parameters must be declared by the selected driver"
    }
    switch family {
    case .nintendoSwitch1:
      if layout == .gameCube { return "GameCube is a Switch 2 layout" }
      // A Bluetooth-only pad has no USB link to lay out.
      if usbProtocol != nil, layout != nil {
        return "a Bluetooth-only Switch pad selects no other layout"
      }
    case .vendorGameSir:
      if variant == .usb, !isEmpty { return "GameSir vendor USB declares no parameters" }
      // An unknown model must not receive a guessed lighting-memory layout.
      if variant == .enhancedHID, (innerGrips != nil) == (lightingMemory != nil) {
        return "GameSir enhanced HID must select exactly one model parameter"
      }
    case .sonyDualShock4:
      if let role, role != .wirelessAdapter { return "a DualShock 4 role is WirelessAdapter" }
      if role != nil, motionScale != nil { return "a DualShock 4 row selects at most one model" }
    case .sonyDualSense:
      if let role, role != .receiver { return "a DualSense role is Receiver" }
      // Every other DualSense parameter describes a third-party model, which means nothing
      // without the mode.
      if maker == nil, !isEmpty { return "DualSense model parameters require maker ThirdParty" }
    default: break
    }
    return nil
  }
}
