import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ProtocolDescriptionTests {
  private static let minimalInput =
    #"{"report": {"length": 1}, "buttons": [{"control": "face-south", "byte": 0, "mask": 1}]}"#
  private static let startupWrite =
    #"{"startup": [{"report": {"kind": "output", "id": 1, "length": 4}, "bytes": [1, 2, 3]}]}"#

  /// Decodes a description of `family` whose body after the header is `body`.
  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", \(body)}
      """
    return try ProtocolDescription.decode(
      Data(json.utf8),
      protocolID: family,
      fileName: "\(family.rawValue).json"
    )
  }

  private func rejection(family: PhysicalProtocolID, _ body: String) -> ProtocolDescriptionProblem?
  {
    do {
      _ = try decode(family: family, body)
      return nil
    } catch { return error }
  }

  // MARK: - Bundled descriptions

  @Test
  func everyFamilyThatDeclaresParametersHasADescription() {
    for family in PhysicalProtocolID.allCases {
      let description = ProtocolDescription.bundled[family]
      if !ProtocolParameters.declared(by: family).isEmpty {
        #expect(description != nil, "\(family.rawValue)")
      }
    }
    #expect(ProtocolDescription.bundled.count == 11)
  }

  /// The parameters a description declares are those `ProtocolParameters` decodes: the names
  /// match, and an enum's values are cases of the Swift enum that holds it.
  @Test
  func declaredParametersMatchTheSwiftParameterTypes() {
    let enums: [String: [String]] = [
      "layout": ProtocolParameters.Layout.allCases.map(\.rawValue),
      "usbProtocol": ProtocolParameters.USBProtocol.allCases.map(\.rawValue),
      "lightingMemory": ProtocolParameters.LightingMemory.allCases.map(\.rawValue),
      "hatSource": ProtocolParameters.HatSource.allCases.map(\.rawValue),
      "motionCalibration": ProtocolParameters.MotionCalibration.allCases.map(\.rawValue),
      "role": ProtocolParameters.Role.allCases.map(\.rawValue),
      "motionScale": ProtocolParameters.MotionScale.allCases.map(\.rawValue),
      "reportRevision": ProtocolParameters.ReportRevision.allCases.map(\.rawValue),
      "usageLayout": ProtocolParameters.UsageLayout.allCases.map(\.rawValue),
      "maker": ProtocolParameters.Maker.allCases.map(\.rawValue),
    ]
    let flags: Set<String> = [
      "innerGrips", "unprobedSensors", "unprobedTouchpad", "forcedVibration",
    ]
    var declared: Set<String> = []
    var enumValues: [String: Set<String>] = [:]
    for description in ProtocolDescription.bundled.values {
      for (name, type) in description.parameters {
        declared.insert(name)
        switch type {
        case .flag: #expect(flags.contains(name), "\(name)")
        case .enumeration(let values):
          #expect(Set(values).isSubset(of: enums[name] ?? []), "\(name)")
          enumValues[name, default: []].formUnion(values)
        case .object(let fields):
          #expect(name == "shareButton")
          #expect(fields == ["fromEnd": ProtocolParameters.ShareButton.fromEndRange])
        }
      }
    }
    #expect(declared == ProtocolParameters.names)
    for (name, values) in enums { #expect(enumValues[name] == Set(values), "\(name)") }
  }

  // MARK: - Defaults

  @Test
  func decodesDefaultsTheirDriverReads() throws {
    let layout = try decode(
      family: .hidReportLayout,
      #""defaults": {"input": \#(Self.minimalInput), "tuning": {"stickDeadzone": 0.1}}"#
    )
    #expect(layout.inputLayout?.controls == [.faceSouth])
    #expect(layout.tuning == ControllerTuning(stickDeadzone: 0.1))

    let hid = try decode(
      family: .sonyDualShock4,
      #""defaults": {"output": \#(Self.startupWrite)}"#
    )
    #expect(hid.startupWrites.count == 1)

    let ds4 = try decode(
      family: .sonyDualShock4,
      #""defaults": {"tuning": {"inputLivenessTimeoutMs": 1500}}"#
    )
    #expect(ds4.tuning == ControllerTuning(inputLivenessTimeoutMilliseconds: 1_500))
  }

  @Test
  func decodesParameterDeclarations() throws {
    let description = try decode(
      family: .sonyDualSense,
      """
      "parameters": {"maker": {"type": "enum", "values": ["ThirdParty"]},
                     "forcedVibration": {"type": "flag"}}
      """
    )
    #expect(
      description.parameters == [
        "maker": .enumeration(["ThirdParty"]), "forcedVibration": .flag,
      ]
    )
    let gip = try decode(
      family: .xboxGIP,
      """
      "parameters": {"shareButton": {"type": "object",
                                      "fields": {"fromEnd": {"type": "integer",
                                                             "minimum": 1, "maximum": 255}}}}
      """
    )
    #expect(gip.parameters == ["shareButton": .object(["fromEnd": 1...255])])
  }

  // MARK: - Rejections

  @Test(
    arguments: [
      (PhysicalProtocolID.sonyDualSense, #""parameters": {"maker": {"type": "string"}}"#),
      (.sonyDualSense, #""parameters": {"maker": {"type": "enum", "values": []}}"#),
      (.sonyDualSense, #""parameters": {"maker": {"type": "enum", "values": ["thirdParty"]}}"#),
      (.sonyDualSense, #""parameters": {"maker": {"type": "flag", "values": ["A"]}}"#),
      (.sonyDualSense, #""parameters": {"unknown": {"type": "flag"}}"#),
      (.sonyDualSense, #""parameters": {}"#),
      (
        .xboxGIP,
        #""parameters": {"shareButton": {"type": "object", "fields": "#
          + #"{"fromEnd": {"type": "integer", "minimum": 9, "maximum": 1}}}}"#
      ),
      (.xboxGIP, #""defaults": {}"#),
      (.xboxGIP, #""defaults": {"output": {}}"#),
      (.xboxGIP, #""defaults": {"unknown": {}}"#),
      (.xboxGIP, #""defaults": {"tuning": {"stickDeadzone": 5}}"#),
      (.xboxGIP, #""interfaceSignatures": []"#),
    ]
  )
  func rejectsAMalformedBody(family: PhysicalProtocolID, body: String) {
    #expect(rejection(family: family, body)?.code == .invalidProtocolDescription, "\(body)")
  }

  @Test
  func rejectsDefaultsTheFamilyDriverDoesNotRead() {
    let cases: [(PhysicalProtocolID, String)] = [
      (.hidDescriptor, #""defaults": {"input": \#(Self.minimalInput)}"#),
      (.xboxGIP, #""defaults": {"output": \#(Self.startupWrite)}"#),
      (.xboxXID, #""defaults": {"tuning": {"hidStartupIntervalMs": 5}}"#),
      (.sonyDualSense, #""defaults": {"tuning": {"inputLivenessTimeoutMs": 5}}"#),
      (.sonyDualSense, #""defaults": {"tuning": {"hidStartupRecoveryRounds": 5}}"#),
    ]
    for (family, body) in cases {
      #expect(rejection(family: family, body)?.code == .invalidProtocolDescription, "\(body)")
    }
  }

  @Test
  func rejectsASignatureForAFamilyWithNoVariants() {
    let signature =
      #""interfaceSignatures": [{"variant": "usb", "interfaceClass": 3, "#
      + #""interfaceSubclass": 0, "interfaceProtocol": 0}]"#
    #expect(rejection(family: .hidDescriptor, signature)?.code == .unknownProtocolVariant)
  }

  @Test
  func everyRejectionCarriesACatalogCode() {
    let problem = rejection(family: .xboxGIP, #""interfaceSignatures": []"#)
    #expect(problem?.description.hasPrefix("E5002: xbox.gip.json: ") == true)
    #expect(ErrorCode.invalidProtocolDescription.domain == .document)
    #expect(ErrorCode.protocolDescriptionFamilyMismatch.domain == .document)
    #expect(ErrorCode.unknownProtocolVariant.domain == .document)
  }
}
