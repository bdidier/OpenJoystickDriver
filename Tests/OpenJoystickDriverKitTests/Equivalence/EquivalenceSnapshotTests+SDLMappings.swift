import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Snapshots the SDL mapping text each virtual HID profile yields today.
///
/// OJD ships no SDL mapping text, so the mapping is derived from what a consumer sees: each
/// control is driven alone through the profile's own report codec, the HID fields its report
/// changes are read from the profile's descriptor, and SDL's macOS order names them: buttons by
/// ascending button usage (`bN`), axes by ascending Generic Desktop usage (`aN`), and the hat as
/// `h0.<mask>`. A control the report cannot carry, or one SDL has no name for, is listed apart.
struct EquivalenceSnapshotSDLMappingTests {
  private struct Probe {
    let control: String
    let state: ControllerState
  }

  private static let sdlNames: [String: String] = [
    "faceSouth": "a", "faceEast": "b", "faceWest": "x", "faceNorth": "y",
    "leftShoulder": "leftshoulder", "rightShoulder": "rightshoulder", "view": "back",
    "menu": "start", "guide": "guide", "leftStickClick": "leftstick",
    "rightStickClick": "rightstick", "share": "misc1", "paddleRight1": "paddle1",
    "paddleLeft1": "paddle2", "paddleRight2": "paddle3", "paddleLeft2": "paddle4",
    "touchpadClick": "touchpad", "leftStickX": "leftx", "leftStickY": "lefty",
    "rightStickX": "rightx", "rightStickY": "righty", "leftTrigger": "lefttrigger",
    "rightTrigger": "righttrigger", "dpadNorth": "dpup", "dpadEast": "dpright",
    "dpadSouth": "dpdown", "dpadWest": "dpleft",
  ]

  private static func probes(for controls: Set<ControlID>) -> [Probe] {
    var result: [Probe] = []
    let digital = controls.subtracting([
      .dpad, .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
    ])
    for control in digital.sorted(by: { $0.rawValue < $1.rawValue }) {
      result.append(Probe(control: "\(control)", state: ControllerState(pressed: [control])))
    }
    let analog: [(ControlID, ControllerState)] = [
      (.leftStickX, ControllerState(leftStick: StickPosition(x: .max, y: .center))),
      (.leftStickY, ControllerState(leftStick: StickPosition(x: .center, y: .max))),
      (.rightStickX, ControllerState(rightStick: StickPosition(x: .max, y: .center))),
      (.rightStickY, ControllerState(rightStick: StickPosition(x: .center, y: .max))),
      (.leftTrigger, ControllerState(leftTrigger: .max)),
      (.rightTrigger, ControllerState(rightTrigger: .max)),
    ]
    for (control, state) in analog where controls.contains(control) {
      result.append(Probe(control: "\(control)", state: state))
    }
    if controls.contains(.dpad) {
      let hats: [(String, HatDirection)] = [
        ("dpadNorth", .north), ("dpadEast", .east), ("dpadSouth", .south), ("dpadWest", .west),
      ]
      for (name, hat) in hats {
        result.append(Probe(control: name, state: ControllerState(hat: hat)))
      }
    }
    return result
  }

  /// The little-endian value of `field` in `report`, which leads with its report ID byte.
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

  /// SDL3-style macOS GUID: bus, CRC, vendor, product, and version, each little-endian 16 bits
  /// followed by two zero bytes except the leading bus and CRC.
  private static func guid(_ identity: VirtualDeviceProfile) -> String {
    let bus = identity.transport == "Bluetooth" ? "05" : "03"
    return bus + "000000" + hex(Int(identity.vendorID)) + "0000" + hex(Int(identity.productID))
      + "0000" + hex(identity.versionNumber) + "0000"
  }

  private static func section(
    for id: VirtualHIDProfileID
  ) throws -> (
    title: String, lines: [String]
  ) {
    let profile = try id.makeProfile()
    let parsed = try #require(HIDReportDescriptorParser.parse(descriptor: profile.descriptor))
    let numbered = parsed.inputReportIDs != [0]
    let buttonUsages = Set(parsed.fields.filter { $0.usagePage == 9 }.map(\.usage)).sorted()
    let axisUsages = Set(
      parsed.fields.filter { $0.usagePage == 1 && (0x30...0x35).contains($0.usage) }.map(\.usage)
    ).sorted()
    let neutral = profile.inputReport(for: .neutral)
    var lines = [
      "profile=\(id.rawValue) vendor=\(profile.identity.vendorID) product=\(profile.identity.productID)"
        + " version=\(profile.identity.versionNumber) name=\(profile.identity.productName)",
      "guid=\(guid(profile.identity))",
      "report length=\(neutral.count) descriptorBytes=\(profile.descriptor.count)",
    ]
    var entries: [String] = []
    var unmapped: [String] = []
    for probe in probes(for: id.representableControls) {
      let report = profile.inputReport(for: probe.state)
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
      let fields = changed.map { "\($0.usagePage):\($0.usage)" }.joined(separator: "+")
      lines.append("probe \(probe.control) fields=[\(fields)] -> \(binding ?? "none")")
      if let binding, let name = Self.sdlNames[probe.control] {
        entries.append("\(name):\(binding)")
      } else {
        unmapped.append(probe.control)
      }
    }
    let identity = profile.identity
    lines.append(
      "mapping=\(Self.guid(identity)),\(identity.productName),\(entries.sorted().joined(separator: ",")),platform:Mac OS X,"
    )
    lines.append("unmapped=\(unmapped.sorted().joined(separator: ","))")
    return (id.rawValue, lines)
  }

  @Test
  func sdlMappingsMatchSnapshot() throws {
    let sections = try VirtualHIDProfileID.allCases.map(Self.section)
    let rendered = EquivalenceSnapshotStore.render(sections)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "sdl-mappings.txt") == nil)
  }
}
