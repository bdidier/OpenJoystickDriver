import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolParametersTests {
  /// One removed `ControllerQuirk` raw value, the family that declared it, and the typed
  /// parameter it became.
  private struct Crosswalk: Sendable {
    let quirk: String
    let family: PhysicalProtocolID
    let json: String
    let parameters: ProtocolParameters
    let entry: String
  }

  private static let crosswalk: [Crosswalk] = [
    Crosswalk(
      quirk: "share-offset",
      family: .xboxGIP,
      json: #"{"shareButton":{"fromEnd":26}}"#,
      parameters: ProtocolParameters(shareButton: .init(fromEnd: 26)),
      entry: "shareButton.fromEnd=26"
    ),
    Crosswalk(
      quirk: "joy-con-left",
      family: .nintendoSwitch1,
      json: #"{"layout":"JoyConLeft"}"#,
      parameters: ProtocolParameters(layout: .joyConLeft),
      entry: "layout=JoyConLeft"
    ),
    Crosswalk(
      quirk: "joy-con-right",
      family: .nintendoSwitch2,
      json: #"{"layout":"JoyConRight"}"#,
      parameters: ProtocolParameters(layout: .joyConRight),
      entry: "layout=JoyConRight"
    ),
    Crosswalk(
      quirk: "gamecube",
      family: .nintendoSwitch2,
      json: #"{"layout":"GameCube"}"#,
      parameters: ProtocolParameters(layout: .gameCube),
      entry: "layout=GameCube"
    ),
    Crosswalk(
      quirk: "bluetooth-only",
      family: .nintendoSwitch1,
      json: #"{"usbProtocol":"ChargingOnly"}"#,
      parameters: ProtocolParameters(usbProtocol: .chargingOnly),
      entry: "usbProtocol=ChargingOnly"
    ),
    Crosswalk(
      quirk: "inner-grips",
      family: .vendorGameSir,
      json: #"{"innerGrips":true}"#,
      parameters: ProtocolParameters(innerGrips: true),
      entry: "innerGrips=true"
    ),
    Crosswalk(
      quirk: "lighting-slots",
      family: .vendorGameSir,
      json: #"{"lightingMemory":"ProfileSlots"}"#,
      parameters: ProtocolParameters(lightingMemory: .profileSlots),
      entry: "lightingMemory=ProfileSlots"
    ),
    Crosswalk(
      quirk: "dpad-pressure",
      family: .vendorPS3ThirdParty,
      json: #"{"hatSource":"DpadPressure"}"#,
      parameters: ProtocolParameters(hatSource: .dpadPressure),
      entry: "hatSource=DpadPressure"
    ),
    Crosswalk(
      quirk: "factory-calibration",
      family: .sonyDualShock4,
      json: #"{"motionCalibration":"Factory"}"#,
      parameters: ProtocolParameters(motionCalibration: .factory),
      entry: "motionCalibration=Factory"
    ),
    Crosswalk(
      quirk: "wireless-adapter",
      family: .sonyDualShock4,
      json: #"{"role":"WirelessAdapter"}"#,
      parameters: ProtocolParameters(role: .wirelessAdapter),
      entry: "role=WirelessAdapter"
    ),
    Crosswalk(
      quirk: "strikepad",
      family: .sonyDualShock4,
      json: #"{"motionScale":"StrikePad"}"#,
      parameters: ProtocolParameters(motionScale: .strikePad),
      entry: "motionScale=StrikePad"
    ),
    Crosswalk(
      quirk: "shield-2015",
      family: .vendorNVIDIAShield,
      json: #"{"reportRevision":"Shield2015"}"#,
      parameters: ProtocolParameters(reportRevision: .shield2015),
      entry: "reportRevision=Shield2015"
    ),
    Crosswalk(
      quirk: "wr007",
      family: .hidDescriptor,
      json: #"{"usageLayout":"Wr007"}"#,
      parameters: ProtocolParameters(usageLayout: .wr007),
      entry: "usageLayout=Wr007"
    ),
    Crosswalk(
      quirk: "scuf-envision",
      family: .hidDescriptor,
      json: #"{"usageLayout":"ScufEnvision"}"#,
      parameters: ProtocolParameters(usageLayout: .scufEnvision),
      entry: "usageLayout=ScufEnvision"
    ),
    Crosswalk(
      quirk: "z-rz-brake-left",
      family: .hidDescriptor,
      json: #"{"usageLayout":"ZRzBrakeLeft"}"#,
      parameters: ProtocolParameters(usageLayout: .zRzBrakeLeft),
      entry: "usageLayout=ZRzBrakeLeft"
    ),
    Crosswalk(
      quirk: "dragonrise",
      family: .hidDescriptor,
      json: #"{"usageLayout":"DragonRise"}"#,
      parameters: ProtocolParameters(usageLayout: .dragonRise),
      entry: "usageLayout=DragonRise"
    ),
    Crosswalk(
      quirk: "third-party",
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty"}"#,
      parameters: ProtocolParameters(maker: .thirdParty),
      entry: "maker=ThirdParty"
    ),
    Crosswalk(
      quirk: "unprobed-sensors",
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","unprobedSensors":true}"#,
      parameters: ProtocolParameters(maker: .thirdParty, unprobedSensors: true),
      entry: "unprobedSensors=true"
    ),
    Crosswalk(
      quirk: "unprobed-touchpad",
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","unprobedTouchpad":true}"#,
      parameters: ProtocolParameters(maker: .thirdParty, unprobedTouchpad: true),
      entry: "unprobedTouchpad=true"
    ),
    Crosswalk(
      quirk: "forced-vibration",
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","forcedVibration":true}"#,
      parameters: ProtocolParameters(maker: .thirdParty, forcedVibration: true),
      entry: "forcedVibration=true"
    ),
    Crosswalk(
      quirk: "receiver",
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","role":"Receiver"}"#,
      parameters: ProtocolParameters(role: .receiver, maker: .thirdParty),
      entry: "role=Receiver"
    ),
  ]

  /// The raw values of the removed `ControllerQuirk` enum.
  private static let removedQuirks: Set<String> = [
    "share-offset", "joy-con-left", "joy-con-right", "bluetooth-only", "gamecube", "inner-grips",
    "lighting-slots", "dpad-pressure", "factory-calibration", "wireless-adapter", "strikepad",
    "shield-2015", "wr007", "scuf-envision", "z-rz-brake-left", "dragonrise", "third-party",
    "unprobed-sensors", "unprobed-touchpad", "forced-vibration", "receiver",
  ]

  private func decode(_ json: String) throws -> ProtocolParameters {
    try JSONDecoder().decode(ProtocolParameters.self, from: Data(json.utf8))
  }

  @Test
  func everyRemovedQuirkLandedInATypedParameter() throws {
    #expect(Set(Self.crosswalk.map(\.quirk)) == Self.removedQuirks)
    #expect(Self.crosswalk.count == Self.removedQuirks.count)
    for row in Self.crosswalk {
      let decoded = try decode(row.json)
      #expect(decoded == row.parameters, "\(row.quirk)")
      #expect(decoded.entries.contains(row.entry), "\(row.quirk)")
      #expect(decoded.violation(family: row.family, variant: nil) == nil, "\(row.quirk)")
    }
  }

  @Test
  func encodingRoundTripsEveryParameter() throws {
    for row in Self.crosswalk {
      let data = try JSONEncoder().encode(row.parameters)
      #expect(try JSONDecoder().decode(ProtocolParameters.self, from: data) == row.parameters)
    }
  }

  @Test(
    arguments: [
      #"{"share-offset":true}"#, #"{"quirks":["share-offset"]}"#, #"{"layout":"joy-con-left"}"#,
      #"{"layout":["JoyConLeft"]}"#, #"{"innerGrips":"yes"}"#, #"{"innerGrips":false}"#,
      #"{"shareButton":26}"#, #"{"shareButton":{"fromEnd":0}}"#,
      #"{"shareButton":{"fromEnd":26,"extra":1}}"#, #"{"maker":"Sony"}"#, #"{}"#,
    ]
  )
  func rejectsUnknownEmptyAndMistypedParameters(json: String) {
    #expect(throws: DecodingError.self) { try decode(json) }
  }

  @Test
  func rejectsAParameterItsFamilyDoesNotDeclare() throws {
    let wrongFamily = try decode(#"{"layout":"JoyConLeft"}"#)
    for family in PhysicalProtocolID.allCases
    where family != .nintendoSwitch1 && family != .nintendoSwitch2 {
      #expect(wrongFamily.violation(family: family, variant: nil) != nil, "\(family)")
    }
    #expect(ProtocolParameters.none.violation(family: .xboxXUSB, variant: .wired) == nil)
  }
}
