/// How a consumer reads one persona's virtual gamepad: its SDL mapping and its W3C description.
///
/// Nothing here is written per persona. Each control is driven alone through the persona's own
/// report codec, the HID fields its report changes are read from the persona's descriptor, and
/// SDL's macOS order names them: buttons by ascending button usage (`bN`), axes by ascending
/// Generic Desktop usage (`aN`), and the hat as `h0.<mask>`. A control the report cannot carry,
/// or one SDL has no name for, is listed in ``unmapped``. The mapping adds no axis modifier,
/// because no derived binding needs one: the report carries each axis in the direction SDL reads.
public struct VirtualGamepadMapping: Equatable, Sendable {
  /// One control driven alone, and the descriptor fields its report changed.
  public struct Probe: Equatable, Sendable {
    public let control: Control
    /// The changed fields as `usagePage:usage`.
    public let fields: [String]
    /// `bN`, `aN` or `h0.<mask>`, or nil when the report carries the control nowhere.
    public let binding: String?
  }

  /// One entry of the W3C standard layout: its index and the device input that supplies it.
  public struct W3CEntry: Equatable, Sendable {
    public let index: Int
    public let control: Control
    /// The same `bN`, `aN` or `h0.<mask>` binding the SDL mapping uses.
    public let source: String
  }

  public let profile: VirtualHIDProfileID
  /// The product name of the persona.
  public let name: String
  /// The SDL3 macOS GUID, with a zero CRC.
  public let guid: String
  public let probes: [Probe]
  /// The controls with no SDL binding, sorted by name.
  public let unmapped: [Control]
  /// The one-line SDL mapping, ending in a comma.
  public let sdlMapping: String
  /// The browser id: product name, vendor and product.
  public let w3cID: String
  /// The standard layout's buttons, ascending by index. A trigger is a button whose source is an
  /// axis.
  public let w3cButtons: [W3CEntry]
  /// The standard layout's axes, ascending by index.
  public let w3cAxes: [W3CEntry]
}

public enum VirtualGamepadMappingError: Error, Equatable, Sendable {
  case descriptorNotParsable(VirtualHIDProfileID)
}

/// What SDL and the W3C Gamepad API call one control. A control absent here has no SDL name.
private struct ControlNames {
  let sdl: String
  let w3cButton: Int?
  let w3cAxis: Int?

  static let table: [Control: Self] = [
    .south: .init(sdl: "a", w3cButton: 0, w3cAxis: nil),
    .east: .init(sdl: "b", w3cButton: 1, w3cAxis: nil),
    .west: .init(sdl: "x", w3cButton: 2, w3cAxis: nil),
    .north: .init(sdl: "y", w3cButton: 3, w3cAxis: nil),
    .leftShoulder: .init(sdl: "leftshoulder", w3cButton: 4, w3cAxis: nil),
    .rightShoulder: .init(sdl: "rightshoulder", w3cButton: 5, w3cAxis: nil),
    .leftTrigger: .init(sdl: "lefttrigger", w3cButton: 6, w3cAxis: nil),
    .rightTrigger: .init(sdl: "righttrigger", w3cButton: 7, w3cAxis: nil),
    .back: .init(sdl: "back", w3cButton: 8, w3cAxis: nil),
    .start: .init(sdl: "start", w3cButton: 9, w3cAxis: nil),
    .leftStickClick: .init(sdl: "leftstick", w3cButton: 10, w3cAxis: nil),
    .rightStickClick: .init(sdl: "rightstick", w3cButton: 11, w3cAxis: nil),
    .dpadUp: .init(sdl: "dpup", w3cButton: 12, w3cAxis: nil),
    .dpadDown: .init(sdl: "dpdown", w3cButton: 13, w3cAxis: nil),
    .dpadLeft: .init(sdl: "dpleft", w3cButton: 14, w3cAxis: nil),
    .dpadRight: .init(sdl: "dpright", w3cButton: 15, w3cAxis: nil),
    .guide: .init(sdl: "guide", w3cButton: 16, w3cAxis: nil),
    .capture: .init(sdl: "misc1", w3cButton: nil, w3cAxis: nil),
    .rightPaddle1: .init(sdl: "paddle1", w3cButton: nil, w3cAxis: nil),
    .leftPaddle1: .init(sdl: "paddle2", w3cButton: nil, w3cAxis: nil),
    .rightPaddle2: .init(sdl: "paddle3", w3cButton: nil, w3cAxis: nil),
    .leftPaddle2: .init(sdl: "paddle4", w3cButton: nil, w3cAxis: nil),
    .touchpadClick: .init(sdl: "touchpad", w3cButton: nil, w3cAxis: nil),
    .leftStickX: .init(sdl: "leftx", w3cButton: nil, w3cAxis: 0),
    .leftStickY: .init(sdl: "lefty", w3cButton: nil, w3cAxis: 1),
    .rightStickX: .init(sdl: "rightx", w3cButton: nil, w3cAxis: 2),
    .rightStickY: .init(sdl: "righty", w3cButton: nil, w3cAxis: 3),
  ]

  /// SDL's canonical field order in a mapping string.
  static let sdlFieldOrder = [
    "a", "b", "x", "y", "back", "guide", "start", "leftstick", "rightstick", "leftshoulder",
    "rightshoulder", "dpup", "dpdown", "dpleft", "dpright", "misc1", "paddle1", "paddle2",
    "paddle3", "paddle4", "touchpad", "leftx", "lefty", "rightx", "righty", "lefttrigger",
    "righttrigger",
  ]
}

extension VirtualHIDProfileID {
  /// The SDL mapping and W3C description this persona's descriptor and report codec yield.
  public func gamepadMapping() throws -> VirtualGamepadMapping {
    let profile = try makeProfile()
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: profile.descriptor) else {
      throw VirtualGamepadMappingError.descriptorNotParsable(self)
    }
    let numbered = parsed.inputReportIDs != [0]
    let buttonUsages = Set(parsed.fields.filter { $0.usagePage == 9 }.map(\.usage)).sorted()
    let axisUsages = Set(
      parsed.fields.filter { $0.usagePage == 1 && (0x30...0x35).contains($0.usage) }.map(\.usage)
    ).sorted()
    let neutral = profile.inputReport(for: .neutral)
    var probes: [VirtualGamepadMapping.Probe] = []
    for (control, state) in Self.probeStates(for: representableControls) {
      let report = profile.inputReport(for: state)
      let changed = parsed.fields.filter {
        Self.value(of: $0, in: report, numbered: numbered)
          != Self.value(of: $0, in: neutral, numbered: numbered)
      }
      var binding: String?
      if let button = changed.first(where: { $0.usagePage == 9 }),
        let index = buttonUsages.firstIndex(of: button.usage)
      {
        binding = "b\(index)"
      } else if let axis = changed.first(where: {
        $0.usagePage == 1 && axisUsages.contains($0.usage)
      }),
        let index = axisUsages.firstIndex(of: axis.usage)
      {
        binding = "a\(index)"
      } else if let hat = changed.first(where: { $0.usagePage == 1 && $0.usage == 0x39 }) {
        let mask = [1: 1, 2: 3, 3: 2, 4: 6, 5: 4, 6: 12, 7: 8, 8: 9]
        let raw = Self.value(of: hat, in: report, numbered: numbered) - hat.logicalMin + 1
        binding = "h0.\(mask[raw] ?? 0)"
      }
      probes.append(
        .init(
          control: control,
          fields: changed.map { "\($0.usagePage):\($0.usage)" },
          binding: binding
        )
      )
    }
    return Self.assemble(self, identity: profile.identity, probes: probes)
  }

  private static func assemble(
    _ id: VirtualHIDProfileID,
    identity: VirtualDeviceProfile,
    probes: [VirtualGamepadMapping.Probe]
  ) -> VirtualGamepadMapping {
    let guid = Self.guid(identity)
    var entries: [(name: String, text: String)] = []
    var unmapped: [Control] = []
    var buttons: [VirtualGamepadMapping.W3CEntry] = []
    var axes: [VirtualGamepadMapping.W3CEntry] = []
    for probe in probes {
      guard let binding = probe.binding, let names = ControlNames.table[probe.control] else {
        unmapped.append(probe.control)
        continue
      }
      let isTrigger = probe.control == .leftTrigger || probe.control == .rightTrigger
      let prefix = isTrigger && binding.hasPrefix("a") ? "+" : ""
      entries.append((names.sdl, "\(names.sdl):\(prefix)\(binding)"))
      if let index = names.w3cButton {
        buttons.append(.init(index: index, control: probe.control, source: binding))
      }
      if let index = names.w3cAxis {
        axes.append(.init(index: index, control: probe.control, source: binding))
      }
    }
    let order = ControlNames.sdlFieldOrder
    let bindings = entries.sorted {
      (order.firstIndex(of: $0.name) ?? order.count)
        < (order.firstIndex(of: $1.name) ?? order.count)
    }.map(\.text).joined(separator: ",")
    let vendor = String(identity.vendorID, radix: 16)
    let product = String(identity.productID, radix: 16)
    return VirtualGamepadMapping(
      profile: id,
      name: identity.productName,
      guid: guid,
      probes: probes,
      unmapped: unmapped.sorted { $0.rawValue < $1.rawValue },
      sdlMapping: "\(guid),\(identity.productName),\(bindings),platform:Mac OS X,",
      w3cID: "\(identity.productName) (Vendor: \(vendor) Product: \(product))",
      w3cButtons: buttons.sorted { $0.index < $1.index },
      w3cAxes: axes.sorted { $0.index < $1.index }
    )
  }

  /// Each control of `controls` with the state that drives it alone: digital controls by name,
  /// then sticks and triggers at full deflection, then the D-pad as hat directions.
  private static func probeStates(for controls: Set<Control>) -> [(Control, ControllerState)] {
    var result: [(Control, ControllerState)] = []
    let digital = controls.subtracting(
      Control.dpad.union([
        .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
      ])
    )
    for control in digital.sorted(by: { $0.rawValue < $1.rawValue }) {
      result.append((control, ControllerState(pressed: [control])))
    }
    let analog: [(Control, ControllerState)] = [
      (.leftStickX, ControllerState(leftStick: StickPosition(x: .max, y: .center))),
      (.leftStickY, ControllerState(leftStick: StickPosition(x: .center, y: .max))),
      (.rightStickX, ControllerState(rightStick: StickPosition(x: .max, y: .center))),
      (.rightStickY, ControllerState(rightStick: StickPosition(x: .center, y: .max))),
      (.leftTrigger, ControllerState(leftTrigger: .max)),
      (.rightTrigger, ControllerState(rightTrigger: .max)),
    ]
    result += analog.filter { controls.contains($0.0) }
    if !controls.isDisjoint(with: Control.dpad) {
      let hats: [(Control, HatDirection)] = [
        (.dpadUp, .north), (.dpadRight, .east), (.dpadDown, .south), (.dpadLeft, .west),
      ]
      result += hats.map { ($0.0, ControllerState(hat: $0.1)) }
    }
    return result
  }

  /// The little-endian value of `field` in `report`, which leads with its report ID byte when
  /// the descriptor numbers its reports.
  private static func value(of field: HIDField, in report: [UInt8], numbered: Bool) -> Int {
    let payload = numbered ? Array(report.dropFirst()) : report
    var value = 0
    for bit in 0..<field.bitSize {
      let position = field.bitOffset + bit
      guard position / 8 < payload.count else { break }
      if payload[position / 8] & (1 << UInt8(position % 8)) != 0 { value |= 1 << bit }
    }
    return value
  }

  private static func hex(_ value: Int) -> String {
    let digits = String(UInt16(truncatingIfNeeded: value), radix: 16)
    let padded = String(repeating: "0", count: 4 - digits.count) + digits
    return String(padded.suffix(2)) + String(padded.prefix(2))
  }

  /// SDL3-style macOS GUID: bus, zero CRC, vendor, product, and version, each little-endian 16
  /// bits followed by two zero bytes except the leading bus and CRC.
  private static func guid(_ identity: VirtualDeviceProfile) -> String {
    let bus = identity.transport == "Bluetooth" ? "05" : "03"
    return bus + "000000" + hex(Int(identity.vendorID)) + "0000" + hex(Int(identity.productID))
      + "0000" + hex(identity.versionNumber) + "0000"
  }
}
