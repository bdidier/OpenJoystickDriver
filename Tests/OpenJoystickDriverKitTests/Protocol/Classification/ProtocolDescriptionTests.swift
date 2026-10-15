import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ProtocolDescriptionTests {
  private static let minimalInput =
    #"{"report": {"length": 1}, "buttons": [{"control": "face-south", "byte": 0, "mask": 1}]}"#
  private static let rumbleTemplate =
    #"{"report": {"kind": "output", "id": 1, "length": 4}, "leftMain": {"byte": 1}}"#
  private static let startupWrite =
    #"{"startup": [{"report": {"kind": "output", "id": 1, "length": 4}, "bytes": [1, 2, 3]}]}"#

  /// Decodes a description of `family` whose body after the header is `body`.
  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", "endpoints": {"in": 130, "out": 2}, \(body)}
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
    #expect(ProtocolDescription.bundled.count == PhysicalProtocolID.allCases.count)
  }

  /// The family facts the drivers read come from the descriptions.
  @Test
  func bundledDescriptionsHoldTheFamilyFacts() throws {
    let bundled = ProtocolDescription.bundled
    #expect(bundled[.xboxXUSB]?.endpoints == .init(input: 129, output: 1))
    #expect(bundled[.xboxXID]?.endpoints == .init(input: 129, output: 2))
    #expect(bundled[.xboxGIP]?.endpoints == .init(input: 130, output: 2))
    #expect(bundled[.xboxXID]?.rawUSB == .always)
    #expect(bundled[.vendorGameSir]?.rawUSB == .variants([.usb]))
    #expect(bundled[.sonyDualSense]?.rawUSB == .never)
    #expect(bundled[.hidReportLayout]?.recordSections == [.input, .rumble])
    #expect(bundled[.vendorPS3ThirdParty]?.recordSections == [.rumble])
    #expect(bundled[.sonyDualShock4]?.buttonLabels == .playStation)
    #expect(bundled[.nintendoSwitch2]?.buttonLabels == .nintendo)
    #expect(bundled[.xboxGIP]?.buttonLabels == .standard)
    #expect(bundled[.sonyDualShock4]?.tuning?.inputLivenessTimeoutMilliseconds == 1_000)
    #expect(bundled[.nintendoSwitch1]?.tuning?.minimumHIDOutputIntervalMilliseconds == 50)
    #expect(bundled[.vendorGameSir]?.tuning?.hidStartupIntervalMilliseconds == 20)
    #expect(bundled[.nintendoSwitch1]?.tuning?.hidStartupRecoveryIntervalMilliseconds == 200)
    #expect(bundled[.nintendoSwitch1]?.tuning?.hidStartupRecoveryRounds == 2)
    #expect(bundled[.nintendoSwitch2]?.keepAlive?.intervalMilliseconds == 12)
    #expect(bundled[.valveSteamDeck]?.keepAlive?.intervalMilliseconds == 1_000)
    #expect(bundled[.valveSteamTriton]?.keepAlive?.intervalMilliseconds == 40)
    #expect(bundled[.xboxGIP]?.keepAlive?.intervalMilliseconds == 4_000)
    #expect(bundled[.vendorGameSir]?.keepAlive?.intervalMilliseconds == 500)
    #expect(bundled[.valveSteamTriton]?.tuning?.lizardResendTicks == 75)
    #expect(bundled[.nintendoSwitch2]?.tuning?.usbCommandTimeoutMilliseconds == 1_000)
    #expect(bundled[.vendorGameSir]?.tuning?.usbCommandTimeoutMilliseconds == 2_000)
    #expect(bundled[.xboxGIP]?.tuning?.presenceResendReports == 4)
    #expect(bundled[.xboxXUSB]?.tuning?.presenceResendReports == 16)
    #expect(bundled[.xboxGIP]?.tuning?.usbStartupIntervalMilliseconds == 50)
    #expect(bundled[.xboxGIP]?.tuning?.usbStartupRetryDelayMilliseconds == 1_000)
    #expect(bundled[.sonyDualShock4]?.tuning?.adapterDisconnectDelayMilliseconds == 500)
    #expect(bundled[.sonyDualSense]?.tuning?.adapterDisconnectDelayMilliseconds == 500)
    let switch1 = try #require(bundled[.nintendoSwitch1])
    #expect(switch1.tuning(variant: .bluetoothClassic)?.hidStartupIntervalMilliseconds == 60)
    #expect(switch1.tuning(variant: .usb)?.hidStartupIntervalMilliseconds == 20)
    #expect(bundled[.sonyDualSense]?.recordCapabilities.presentControls.count == 4)
    #expect(bundled[.xboxGIP]?.recordCapabilities.rumbleAbsent == true)
    let sixaxis = try #require(bundled[.sonySixaxis]).macOSOwnedOutput
    #expect(sixaxis.drivesRumble && sixaxis.setsStartupPlayerIndicator)
    #expect(
      sixaxis.reports == [ControllerTemplateReport(kind: .output, reportID: 0x01, length: 49)]
    )
  }

  /// A raw-USB variant reads no HID timing.
  @Test
  func tuningScopeFollowsTheDescription() {
    let gameSir = ControllerTuning.scope(protocolID: .vendorGameSir, variant: .usb)
    #expect(
      gameSir == [.stickDeadzone, .frameQueueCapacity, .usbCommandTimeoutMs]
    )
    let enhanced = ControllerTuning.scope(protocolID: .vendorGameSir, variant: .enhancedHID)
    #expect(
      enhanced == [
        .stickDeadzone, .frameQueueCapacity, .hidStartupIntervalMs, .minimumHIDOutputIntervalMs,
      ]
    )
    #expect(
      ControllerTuning.scope(protocolID: .xboxGIP, variant: nil)
        == [
          .stickDeadzone, .frameQueueCapacity, .presenceResendReports, .usbStartupIntervalMs,
          .usbStartupRetryDelayMs, .usbTransferTimeoutMs,
        ]
    )
    #expect(
      ControllerTuning.scope(protocolID: nil, variant: nil) == [
        .stickDeadzone, .frameQueueCapacity,
      ]
    )
    #expect(
      ControllerTuning.scope(protocolID: .sonyDualShock4, variant: nil)
        .contains(.inputLivenessTimeoutMs)
    )
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
  func everyBundledDescriptionDefaultsTheFrameQueueCapacityToTheSenderFallback() {
    for (family, description) in ProtocolDescription.bundled {
      #expect(
        description.tuning?.frameQueueCapacity == UserSpaceReportSender.fallbackQueueCapacity,
        "\(family)"
      )
    }
  }

  @Test
  func decodesDefaultsTheirDriverReads() throws {
    let layout = try decode(
      family: .hidReportLayout,
      #""recordSections": ["input"], "#
        + #""defaults": {"input": \#(Self.minimalInput), "tuning": {"stickDeadzone": 0.1}}"#
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
      #""tuningKeys": ["inputLivenessTimeoutMs"], "#
        + #""defaults": {"tuning": {"inputLivenessTimeoutMs": 1500}}"#
    )
    #expect(ds4.tuning == ControllerTuning(inputLivenessTimeoutMilliseconds: 1_500))
  }

  @Test
  func anXboxXIDDescriptionMayDeclareAnInputLayout() throws {
    let description = try decode(
      family: .xboxXID,
      #""rawUSB": true, "recordSections": ["input"], "#
        + #""defaults": {"input": \#(Self.minimalInput)}"#
    )
    #expect(description.inputLayout?.controls == [.faceSouth])
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

  /// `ProtocolParameters.violation` takes the ranges and enum values from the description.
  @Test
  func parameterViolationsReadTheDescription() {
    var parameters = ProtocolParameters()
    parameters.shareButton = .init(fromEnd: 300)
    #expect(
      parameters.violation(family: .xboxGIP, variant: nil)
        == "shareButton.fromEnd must be in 1...255"
    )
    parameters.shareButton = .init(fromEnd: 2)
    #expect(parameters.violation(family: .xboxGIP, variant: nil) == nil)
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
      (.xboxGIP, #""defaults": {"capabilities": {"rumble": "absent"}}"#),
      (.xboxGIP, #""defaults": {"tuning": {"stickDeadzone": 5}}"#),
      (.xboxGIP, #""interfaceSignatures": []"#),
      (.xboxGIP, #""rawUSB": true, "tuningKeys": ["keepAliveIntervalMs"]"#),
      (.sonyDualSense, #""rawUSBTuningKeys": ["keepAliveIntervalMs"]"#),
      (.sonyDualSense, #""defaults": {"variants": {"usb": {"tuning": {"stickDeadzone": 5}}}}"#),
      (.sonyDualSense, #""macOSOwnedOutput": {"rationale": 5}"#),
      (.xboxGIP, #""defaults": {"output": {"rumble": \#(Self.rumbleTemplate)}}"#),
      (.sonyDualSense, #""tuningKeys": ["stickDeadzone"]"#),
      (.xboxGIP, #""rawUSB": true, "rawUSBTuningKeys": ["stickDeadzone"]"#),
    ]
  )
  func rejectsAMalformedBody(family: PhysicalProtocolID, body: String) {
    #expect(rejection(family: family, body)?.code == .invalidProtocolDescription, "\(body)")
  }

  @Test
  func rejectsDefaultsTheFamilyDriverDoesNotRead() {
    let cases: [(PhysicalProtocolID, String)] = [
      (.hidDescriptor, #""defaults": {"input": \#(Self.minimalInput)}"#),
      (.xboxXUSB, #""defaults": {"input": \#(Self.minimalInput)}"#),
      (.xboxGIP, #""rawUSB": true, "defaults": {"output": \#(Self.startupWrite)}"#),
      (.xboxXID, #""rawUSB": true, "defaults": {"tuning": {"hidStartupIntervalMs": 5}}"#),
      (.sonyDualSense, #""defaults": {"tuning": {"hidStartupIntervalMs": 5}}"#),
      (
        .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"tuning": {"inputLivenessTimeoutMs": 5}}"#
      ),
      (.sonyDualSense, #""defaults": {"tuning": {"hidStartupRecoveryRounds": 5}}"#),
    ]
    for (family, body) in cases {
      #expect(rejection(family: family, body)?.code == .invalidProtocolDescription, "\(body)")
    }
  }

  private static let hidReport = #""report": {"kind": "output", "id": 1, "length": 4}"#

  private func startup(_ write: String) -> String {
    #""defaults": {"output": {"startup": ["# + write + "]}}"
  }

  private func hidWrite(_ field: String) -> String {
    "{\(Self.hidReport), \"bytes\": [1, 2, 3]" + (field.isEmpty ? "}" : ", \(field)}")
  }

  @Test
  func decodesStartupWritesOfBothFormats() throws {
    let hid = try decode(
      family: .sonyDualSense,
      startup(
        hidWrite(
          #""phase": "startup", "delayMilliseconds": 5, "variants": ["usb"]"#
        )
      )
    )
    #expect(hid.startupWrites(phase: .startup, variant: .usb, parameters: .none).count == 1)
    #expect(
      hid.startupWrites(phase: .startup, variant: .bluetoothClassic, parameters: .none).isEmpty
    )
    #expect(hid.startupWrites(phase: .activation, variant: .usb, parameters: .none).isEmpty)
    let usb = try decode(
      family: .xboxGIP,
      #""rawUSB": true, "#
        + startup(
          #"{"bytes": [1, 2], "endpoint": 2, "timeoutMilliseconds": 500, "#
            + #""delayMilliseconds": 5, "sessionByte": 1, "toleratesRejection": true}"#
        )
    )
    #expect(usb.usbStartupWrites(variant: nil, parameters: .none).count == 1)
  }

  @Test(
    arguments: [
      #""phase": "later""#, #""delayMilliseconds": 1001"#, #""crc32Seed": 256"#,
      #""crc32Seed": 1"#, #""variants": []"#, #""variants": ["usb", "usb"]"#,
      #""when": {"parameter": "layout", "is": []}"#, #""when": {"parameter": "layout"}"#,
    ]
  )
  func rejectsAMalformedHIDStartupWrite(field: String) {
    let problem = rejection(family: .sonyDualSense, startup(hidWrite(field)))
    #expect(problem?.code == .invalidProtocolDescription, "\(field)")
  }

  @Test(
    arguments: [
      #""endpoint": 0"#, #""endpoint": 128"#, #""timeoutMilliseconds": 0"#,
      #""timeoutMilliseconds": 60001"#, #""delayMilliseconds": 1001"#,
      #""delayMilliseconds": -1"#, #""sessionByte": 64"#, #""toleratesRejection": 1"#,
    ]
  )
  func rejectsAMalformedUSBStartupWrite(field: String) {
    let body = #""rawUSB": true, "# + startup(#"{"bytes": [1], "# + field + "}")
    #expect(rejection(family: .xboxGIP, body)?.code == .invalidProtocolDescription, "\(field)")
  }

  @Test
  func rejectsStartupWritesMixingBothFormats() {
    let body = startup(hidWrite("") + #", {"bytes": [1]}"#)
    #expect(rejection(family: .sonyDualSense, body)?.code == .invalidProtocolDescription)
  }

  @Test
  func rejectsAStartupWriteNamingWhatTheFamilyLacks() {
    let variant = rejection(family: .sonyDualSense, startup(hidWrite(#""variants": ["wired"]"#)))
    #expect(variant?.code == .unknownProtocolVariant)
    let layout = #""when": {"parameter": "layout", "is": ["Pro"]}"#
    #expect(
      rejection(family: .sonyDualSense, startup(hidWrite(layout)))?.code
        == .invalidProtocolDescription
    )
    let value = #""when": {"parameter": "layout", "is": ["Triangle"]}"#
    #expect(
      rejection(family: .nintendoSwitch1, startup(hidWrite(value)))?.code
        == .invalidProtocolDescription
    )
  }

  @Test
  func rejectsAVariantTheFamilyDoesNotHave() {
    #expect(
      rejection(family: .vendorGameSir, #""rawUSB": ["wired"]"#)?.code == .unknownProtocolVariant
    )
    #expect(
      rejection(
        family: .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"variants": {"wired": {"tuning": {"hidStartupIntervalMs": 5}}}}"#
      )?.code == .unknownProtocolVariant
    )
  }

  @Test
  func rejectsRumbleDefaultsAndStickDeadzoneForTheRightReason() {
    let rumble = rejection(
      family: .xboxGIP,
      #""defaults": {"output": {"rumble": \#(Self.rumbleTemplate)}}"#
    )
    #expect(rumble?.description.contains("rumble templates require") == true)
    let deadzone = rejection(family: .sonyDualSense, #""tuningKeys": ["stickDeadzone"]"#)
    #expect(deadzone?.code == .invalidProtocolDescription)
    #expect(deadzone?.description.contains("stickDeadzone") == true)
  }

  @Test
  func rejectsAVariantTuningKeyOutsideTheVariantScope() {
    #expect(
      rejection(
        family: .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"variants": {"usb": {"tuning": {"adapterDisconnectDelayMs": 7}}}}"#
      )?.code == .invalidProtocolDescription
    )
  }

  @Test
  func variantTuningLayersOverTheFlatTuningWithinTheVariantScope() throws {
    let description = try decode(
      family: .sonyDualSense,
      #""tuningKeys": ["hidStartupIntervalMs", "minimumHIDOutputIntervalMs"], "#
        + #""defaults": {"tuning": {"hidStartupIntervalMs": 5, "minimumHIDOutputIntervalMs": 9}, "#
        + #""variants": {"usb": {"tuning": {"hidStartupIntervalMs": 7}}}}"#
    )
    let usb = description.tuning(variant: .usb)
    #expect(usb?.hidStartupIntervalMilliseconds == 7)
    #expect(usb?.minimumHIDOutputIntervalMilliseconds == 9)
    #expect(description.tuning(variant: .bluetoothClassic)?.hidStartupIntervalMilliseconds == 5)
    #expect(
      rejection(
        family: .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"variants": {"usb": {"tuning": {"keepAliveIntervalMs": 7}}}}"#
      )?.code == .invalidProtocolDescription
    )
  }

  /// The spec scenario: a family's interval is edited in its description, and every record of
  /// the family follows it. A record has no interval of its own.
  @Test
  func aFamilysKeepAliveIntervalComesFromItsDescription() throws {
    let edited = try decode(
      family: .valveSteamDeck,
      #""defaults": {"session": {"keepAlive": {"intervalMilliseconds": 777}}}"#
    )
    let plan = DriverSessionPlan(keepAliveChannels: [.hid]).withKeepAlive(of: edited)
    #expect(plan.hidKeepAliveIntervalNanoseconds == 777_000_000)

    let families: Set<PhysicalProtocolID> = [
      .xboxGIP, .vendorGameSir, .valveSteamDeck, .valveSteamTriton, .nintendoSwitch2,
    ]
    var checked: Set<PhysicalProtocolID> = []
    for record in ControllerRecordSet.bundled.records.values {
      let profile = record.profile
      guard families.contains(profile.physicalProtocolID) else { continue }
      let variant =
        profile.physicalProtocolVariant
        ?? (profile.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
      guard
        case .success(let driver) = ProtocolDriverRegistry.makeUnobservedDriver(
          protocolID: profile.physicalProtocolID,
          variant: variant,
          record: profile,
          model: record.model,
          transportProfile: profile.transportProfile
        )
      else { continue }
      let plan = driver.sessionPlan.tuned(profile.tuning)
      let intervals = [plan.usbKeepAliveIntervalNanoseconds, plan.hidKeepAliveIntervalNanoseconds]
        .compactMap { $0 }
      guard !intervals.isEmpty else { continue }
      let described = try #require(
        profile.physicalProtocolID.protocolDescription.keepAlive?.intervalMilliseconds
      )
      for interval in intervals {
        #expect(interval == UInt64(described) * 1_000_000, "\(record.model)")
      }
      checked.insert(profile.physicalProtocolID)
    }
    #expect(checked == families)
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
