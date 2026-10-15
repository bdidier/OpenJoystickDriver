import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordDocumentTests {
  @Test
  func decodesCurrentVocabulary() throws {
    let document = try decode(
      protocol: [
        "family": "xbox.gip", "parameters": ["shareButton": ["fromEnd": 26]],
        "initialization": ["xbox.gip/hori-ack", "xbox.gip/power-on"],
      ],
      usb: ["configuration": "set1-before-claim"],
      capabilities: ["absent": ["LeftTrigger", "RightTrigger"], "rumble": "absent"]
    )

    #expect(document.protocolInfo.protocolID == .xboxGIP)
    #expect(document.protocolInfo.protocolVariant == nil)
    #expect(document.protocolInfo.parameters == ProtocolParameters(shareButton: .init(fromEnd: 26)))
    #expect(document.protocolInfo.initialization == ["xbox.gip/hori-ack", "xbox.gip/power-on"])
    #expect(
      document.capabilities
        == ControllerCapabilityDelta(
          absentControls: [.leftTrigger, .rightTrigger],
          presentControls: [],
          rumbleAbsent: true
        )
    )
    #expect(document.usb?.configuration == "set1-before-claim")
  }

  @Test
  func decodesGameSirModelParameters() throws {
    let cases: [([String: any Sendable], ProtocolParameters)] = [
      (["innerGrips": true], ProtocolParameters(innerGrips: true)),
      (["lightingMemory": "ProfileSlots"], ProtocolParameters(lightingMemory: .profileSlots)),
    ]
    for (parameters, expected) in cases {
      let document = try decode(protocol: [
        "family": "vendor.gamesir", "variant": "enhanced-hid", "parameters": parameters,
      ])
      #expect(document.protocolInfo.protocolVariant == .enhancedHID)
      #expect(document.protocolInfo.parameters == expected)
    }
  }

  @Test
  func decodesThirdPartyDualSenseModelParameters() throws {
    let document = try decode(
      protocol: [
        "family": "sony.dualsense",
        "parameters": [
          "maker": "ThirdParty", "unprobedSensors": true, "unprobedTouchpad": true,
          "forcedVibration": true, "role": "Receiver",
        ] as [String: any Sendable],
      ],
      vendorID: 0x1532
    )
    #expect(
      document.protocolInfo.parameters
        == ProtocolParameters(
          role: .receiver,
          maker: .thirdParty,
          unprobedSensors: true,
          unprobedTouchpad: true,
          forcedVibration: true
        )
    )
  }

  @Test
  func rejectsDualSenseModelParametersWithoutTheThirdPartyMaker() {
    for vendorID in [0x054C, 0x1532] {
      for parameters in [["role": "Receiver"], ["unprobedTouchpad": true]]
        as [[String: any Sendable]]
      {
        #expect(throws: DecodingError.self) {
          try decode(
            protocol: ["family": "sony.dualsense", "parameters": parameters],
            vendorID: vendorID
          )
        }
      }
    }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter(\.storesVariant))
  func decodesEveryStoredVariant(family: PhysicalProtocolID) throws {
    for variant in family.variants {
      var protocolInfo: [String: any Sendable] = [
        "family": family.rawValue, "variant": variant.rawValue,
      ]
      // Enhanced HID rows must name their model parameter.
      if variant == .enhancedHID { protocolInfo["parameters"] = ["innerGrips": true] }
      let document = try decode(protocol: protocolInfo)
      #expect(document.protocolInfo.protocolID == family)
      #expect(document.protocolInfo.protocolVariant == variant)
    }
    #expect(throws: DecodingError.self) { try decode(protocol: ["family": family.rawValue]) }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter { !$0.storesVariant })
  func rejectsVariantsTheTransportDecides(family: PhysicalProtocolID) throws {
    // A report-layout row must carry its layout; any other row must not.
    let extra: [String: any Sendable] =
      family == .hidReportLayout ? ["input": Self.minimalInput] : [:]
    let document = try decode(protocol: ["family": family.rawValue], extra: extra)
    #expect(document.protocolInfo.protocolID == family)
    #expect(document.protocolInfo.protocolVariant == nil)
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": family.rawValue, "variant": "usb"], extra: extra)
    }
  }

  @Test(
    arguments: [
      ["driver": "GIP", "variant": "xboxOne"], ["driver": "GIP"], ["family": "GIP"],
      ["family": "xbox.gip", "variant": "xboxOne"], ["family": "xbox.xusb", "variant": "xbox360"],
      ["family": "xbox.xusb", "variant": "dongle"], ["family": "xbox.xusb:wired"],
      ["family": "vendor.gamesir", "variant": "gameSirG7ProUSB"],
      ["family": "vendor.gamesir", "variant": "enhanced-hid-8k"],
      ["family": "xbox.gip", "parameters": ["innerGrips": true]],
      ["family": "xbox.gip", "quirks": ["share-offset"]],
      ["family": "vendor.gamesir", "variant": "enhanced-hid", "parameters": ["inner-grips": true]],
      ["family": "vendor.gamesir", "variant": "enhanced-hid", "parameters": ["innerGrips": "yes"]],
      ["family": "vendor.gamesir", "variant": "enhanced-hid", "parameters": ["innerGrips": false]],
      ["family": "vendor.gamesir", "variant": "usb", "parameters": ["innerGrips": true]],
      [
        "family": "vendor.gamesir", "variant": "usb",
        "parameters": ["lightingMemory": "ProfileSlots"],
      ],
      ["family": "vendor.gamesir", "variant": "enhanced-hid"],
      ["family": "vendor.gamesir", "variant": "enhanced-hid", "parameters": [String: Bool]()],
      [
        "family": "vendor.gamesir", "variant": "enhanced-hid",
        "parameters": ["innerGrips": true, "lightingMemory": "ProfileSlots"]
          as [String: any Sendable],
      ],
      [
        "family": "vendor.gamesir", "variant": "enhanced-hid",
        "parameters": ["lightingMemory": "profile-slots"],
      ],
      [
        "family": "valve.steam-controller", "variant": "wired",
        "parameters": ["wirelessReceiver": true],
      ],
      ["family": "xbox.adaptive-joystick"],
      ["family": "xbox.gip", "parameters": ["shareOffset": true]],
      ["family": "xbox.gip", "parameters": ["shareButton": ["fromEnd": 0]]],
      ["family": "xbox.gip", "parameters": ["shareButton": ["fromEnd": 256]]],
      ["family": "xbox.gip", "parameters": ["shareButton": ["fromEnd": "26"]]],
      ["family": "xbox.gip", "parameters": ["shareButton": ["fromEnd": 26, "from": 1]]],
      ["family": "xbox.gip", "parameters": ["shareButton": 26]],
      ["family": "xbox.gip", "parameters": ["inputOnly": true]],
      ["family": "xbox.gip", "parameters": ["triggersToButtons": true]],
      ["family": "xbox.xid", "variant": "gamepad", "parameters": ["sticksToNull": true]],
      ["family": "xbox.xusb", "variant": "wired", "parameters": ["dpadToButtons": true]],
      ["family": "xbox.xusb", "variant": "wired", "parameters": ["shareButton": ["fromEnd": 26]]],
      ["family": "sony.dualsense", "parameters": ["edgeButtons": true]],
      ["family": "sony.dualsense", "parameters": ["touchpad": true]],
      ["family": "valve.steam-controller", "variant": "wired", "parameters": ["lizardMode": true]],
      ["family": "nintendo.switch1", "parameters": ["joyConLeft": true]],
      ["family": "nintendo.switch1", "parameters": ["layout": "joy-con-left"]],
      ["family": "nintendo.switch1", "parameters": ["layout": ["JoyConLeft"]]],
      ["family": "nintendo.switch-input-only", "parameters": ["layout": "JoyConLeft"]],
      [
        "family": "nintendo.switch1",
        "parameters": ["usbProtocol": "ChargingOnly", "layout": "JoyConLeft"],
      ],
      ["family": "nintendo.switch1", "parameters": ["usbProtocol": "Wired"]],
      ["family": "nintendo.switch2", "parameters": ["usbProtocol": "ChargingOnly"]],
      ["family": "nintendo.switch1", "parameters": ["layout": "GameCube"]],
      ["family": "vendor.ps3-third-party", "parameters": ["inputOnly": true]],
      ["family": "vendor.ps3-third-party", "parameters": ["hatSource": "dpad-pressure"]],
      ["family": "valve.steam-controller", "variant": "wired", "parameters": ["triton": true]],
      ["family": "valve.steam-triton"], ["family": "valve.steam-deck", "variant": "wired"],
      ["family": "sony.dualshock4", "parameters": ["gyro": true]],
      [
        "family": "sony.dualshock4",
        "parameters": ["role": "WirelessAdapter", "motionScale": "StrikePad"],
      ],
      ["family": "sony.dualshock4", "parameters": ["role": "Receiver"]],
      ["family": "sony.dualshock4", "parameters": ["reportRevision": "Shield2015"]],
      ["family": "vendor.nvidia-shield", "parameters": ["motionCalibration": "Factory"]],
      ["family": "hid.descriptor", "parameters": ["usageLayout": "Wr007"]],
      ["family": "hid.descriptor", "parameters": ["role": "WirelessAdapter"]],
      ["family": "sony.dualshock4", "parameters": ["usageLayout": "Wr007"]],
      ["family": "sony.dualsense", "parameters": ["role": "WirelessAdapter"]],
      ["family": "xbox.gip", "startupPackets": ["xbox.gip/power-on"]],
      ["family": "xbox.gip", "initialization": ["powerOn"]],
      ["family": "xbox.gip", "initialization": ["xbox.gip/missing"]],
      ["family": "xbox.gip", "initialization": ["xbox.gip/power-on", "xbox.gip/power-on"]],
      ["family": "xbox.gip", "initialization": [String]()],
      ["family": "xbox.xusb", "variant": "wired", "initialization": ["xbox.gip/power-on"]],
      ["family": "xbox.xusb", "variant": "wired", "keepAlive": false],
    ] as [[String: any Sendable]]
  )
  func rejectsRemovedProtocolVocabulary(protocolInfo: [String: any Sendable]) {
    #expect(throws: DecodingError.self) { try decode(protocol: protocolInfo) }
  }

  @Test
  func rejectsTheRemovedTransportField() {
    for transport in ["usb", "hid"] {
      #expect(throws: DecodingError.self) {
        try decode(protocol: ["family": "xbox.gip"], extra: ["transport": transport])
      }
    }
  }

  @Test(
    arguments: [
      [:], ["absent": [String]()], ["absent": ["LeftTrigger", "LeftTrigger"]],
      ["absent": ["leftTrigger"]], ["present": ["trackpad"]],
      ["absent": ["Guide"], "present": ["Guide"]], ["rumble": "present"],
      ["rumble": "absent", "controls": ["Guide"]],
    ] as [[String: any Sendable]]
  )
  func rejectsInvalidCapabilities(capabilities: [String: any Sendable]) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "xbox.gip"], capabilities: capabilities)
    }
  }

  @Test
  func presentControlsAreOnlyTheDualSenseEdgeSet() throws {
    let edge = ["LeftPaddle1", "RightPaddle1", "Auxiliary1", "Auxiliary2"]
    let dualSense: [String: any Sendable] = ["family": "sony.dualsense"]
    let document = try decode(protocol: dualSense, capabilities: ["present": edge])
    #expect(document.capabilities.presentControls == DualSenseDriver.edgeControls)
    #expect(throws: DecodingError.self) {
      try decode(protocol: dualSense, capabilities: ["present": Array(edge.prefix(2))])
    }
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "xbox.gip"], capabilities: ["present": ["LeftPaddle1"]])
    }
  }

  @Test
  func rejectsRumbleAbsenceForDriversThatDoNotDeclareIt() {
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: ["family": "xbox.xusb", "variant": "wired"],
        capabilities: ["rumble": "absent"]
      )
    }
  }

  @Test
  func rejectsUSBInterfaceOverride() {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "xbox.gip"], usb: ["interface": 1])
    }
  }

  /// The assembly vocabulary is empty until a row with multi-interface evidence adds a policy.
  @Test(arguments: ["", "steam-dongle", "flydigi-xinput-vendor", "joy-con-pair"])
  func rejectsEveryAssemblyPolicy(name: String) {
    #expect(ControllerAssemblyPolicy(name: name) == nil)
    #expect(throws: DecodingError.self) {
      try decode(protocol: [
        "family": "valve.steam-controller", "variant": "dongle", "assembly": name,
      ])
    }
  }

  @Test
  func noCatalogRowNamesAnAssemblyPolicy() {
    let registry = ProtocolDriverRegistry()
    for model in registry.hidModels + registry.rawUSBModels {
      let record = registry.record(for: model)
      #expect(record?.assemblyPolicy == nil)
      let binding = ProtocolBinding(
        protocolID: record?.physicalProtocolID ?? .hidDescriptor,
        variant: record?.physicalProtocolVariant,
        accessBackend: .ioHID,
        interfaceNumber: nil,
        rule: .catalogRecord,
        matchedPredicates: [.catalogIdentity],
        record: record
      )
      #expect(registry.assemblyPolicy(for: binding) == nil)
    }
  }

  @Test
  func schemaVocabularyMatchesTheSwiftEnums() throws {
    let schema = try Self.controllerSchema()
    let definitions = try #require(schema["$defs"] as? [String: Any])
    // The description defines the ids; the schema holds only their shape.
    let action = try #require(definitions["gipInitializationAction"] as? [String: Any])
    let pattern = try #require(action["pattern"] as? String)
    let identifiers = try #require(
      ProtocolDescription.bundled[.xboxGIP]?.namedPackets?.packets.map(\.id)
    )
    #expect(!identifiers.isEmpty)
    for identifier in identifiers {
      #expect(identifier.range(of: pattern, options: .regularExpression) != nil, "\(identifier)")
    }

    // Every implemented family has catalog rows, so the schema lists all of them.
    let protocolSchema = try #require(definitions["protocol"] as? [String: Any])
    let properties = try #require(protocolSchema["properties"] as? [String: Any])
    #expect(Self.enumValues(properties["family"]) == PhysicalProtocolID.allCases.map(\.rawValue))
    #expect(
      Self.enumValues(properties["assembly"]) == ControllerAssemblyPolicy.allCases.map(\.name)
    )
    let storedVariants = PhysicalProtocolID.allCases.filter(\.storesVariant).flatMap(\.variants)
    #expect(
      Set(Self.enumValues(properties["variant"]) ?? []) == Set(storedVariants.map(\.rawValue))
    )

    let branches = try #require(protocolSchema["allOf"] as? [[String: Any]])
    var declaredParameters: Set<String> = []
    var familiesWithVariants: [PhysicalProtocolID] = []
    for branch in branches {
      for name in Self.familyNames(branch) {
        guard let family = PhysicalProtocolID(rawValue: name),
          let then = branch["then"] as? [String: Any],
          let thenProperties = then["properties"] as? [String: Any]
        else { continue }
        if let variants = Self.enumValues(thenProperties["variant"]) {
          #expect(variants == family.variants.map(\.rawValue), "\(name)")
          familiesWithVariants.append(family)
        }
        if let parameters = thenProperties["parameters"] as? [String: Any] {
          let schemas = parameters["properties"] as? [String: Any] ?? [:]
          #expect(Set(schemas.keys) == ProtocolParameters.declared(by: family), "\(name)")
          #expect(parameters["additionalProperties"] as? Bool == false, "\(name)")
          declaredParameters.formUnion(schemas.keys)
          for (parameter, values) in Self.parameterEnums {
            guard let schemaValues = Self.enumValues(schemas[parameter]) else { continue }
            #expect(Set(schemaValues).isSubset(of: values), "\(name) \(parameter)")
            if parameter != "layout", parameter != "role" {
              #expect(schemaValues == values, "\(name) \(parameter)")
            }
          }
        }
      }
    }
    #expect(familiesWithVariants == PhysicalProtocolID.allCases.filter(\.storesVariant))
    #expect(declaredParameters == ProtocolParameters.names)
  }

  /// An input layout belongs to the `hid.report-layout` family, which cannot run without one.
  @Test
  func inputLayoutIsRequiredExactlyForTheReportLayoutFamily() throws {
    let document = try decode(
      protocol: ["family": "hid.report-layout"],
      extra: ["input": Self.minimalInput]
    )
    #expect(document.inputLayout?.controls == [.south])
    #expect(throws: DecodingError.self) { try decode(protocol: ["family": "hid.report-layout"]) }
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "hid.descriptor"], extra: ["input": Self.minimalInput])
    }
  }

  /// The smallest valid `input` section: one button in a one-byte report.
  static let minimalInput: [String: any Sendable] = [
    "report": ["length": 1] as [String: Int],
    "buttons": [["control": "South", "byte": 0, "mask": 1] as [String: any Sendable]],
  ]

  @Test
  func decodesTuningWhereADriverReadsIt() throws {
    let ds4 = try decode(
      protocol: ["family": "sony.dualshock4"],
      extra: ["tuning": ["stickDeadzone": 0.05, "inputLivenessTimeoutMs": 1_500]]
    )
    #expect(
      ds4.tuning
        == ControllerTuning(stickDeadzone: 0.05, inputLivenessTimeoutMilliseconds: 1_500)
    )
    let switch1 = try decode(
      protocol: ["family": "nintendo.switch1"],
      extra: [
        "tuning": [
          "hidStartupIntervalMs": 40, "hidStartupRecoveryIntervalMs": 300,
          "hidStartupRecoveryRounds": 4,
        ]
      ]
    )
    #expect(
      switch1.tuning
        == ControllerTuning(
          hidStartupIntervalMilliseconds: 40,
          hidStartupRecoveryIntervalMilliseconds: 300,
          hidStartupRecoveryRounds: 4
        )
    )
    #expect(try decode(protocol: ["family": "xbox.gip"]).tuning == .none)
  }

  @Test(arguments: ["xbox.gip", "sony.dualsense", "nintendo.switch2", "hid.descriptor"])
  func decodesFrameQueueCapacityForEveryFamily(family: String) throws {
    let record = try decode(
      protocol: ["family": family],
      extra: ["tuning": ["frameQueueCapacity": 8]]
    )
    #expect(record.tuning == ControllerTuning(frameQueueCapacity: 8))
  }

  @Test(
    arguments: [
      ("sony.dualshock4", ["stickDeadzone": 0]), ("sony.dualshock4", ["stickDeadzone": 1]),
      ("sony.dualshock4", ["inputLivenessTimeoutMs": 0]),
      ("nintendo.switch1", ["hidStartupRecoveryRounds": 11]),
      ("nintendo.switch1", ["hidStartupRecoveryIntervalMs": 0]),
      ("hid.descriptor", ["minimumHIDOutputIntervalMs": 60_001]),
      ("hid.descriptor", ["deadzone": 0.1]), ("hid.descriptor", [:]),
      ("hid.descriptor", ["inputLivenessTimeoutMs": 1_000]),
      ("sony.dualsense", ["hidStartupRecoveryRounds": 2]),
      ("xbox.gip", ["hidStartupIntervalMs": 20]),
      ("valve.steam-triton", ["lizardResendTicks": 0]),
      ("valve.steam-triton", ["lizardResendTicks": 100_001]),
      ("nintendo.switch2", ["usbCommandTimeoutMs": 0]),
      ("nintendo.switch2", ["usbCommandTimeoutMs": 60_001]),
      ("xbox.gip", ["presenceResendReports": 0]),
      ("xbox.gip", ["presenceResendReports": 1_001]),
      ("xbox.xusb", ["presenceResendReports": 0]),
      ("xbox.xusb", ["presenceResendReports": 1_001]),
      ("sony.dualshock4", ["adapterDisconnectDelayMs": 0]),
      ("sony.dualshock4", ["adapterDisconnectDelayMs": 60_001]),
      ("xbox.gip", ["usbStartupIntervalMs": -1]),
      ("xbox.gip", ["usbStartupIntervalMs": 60_001]),
      ("xbox.gip", ["usbStartupRetryDelayMs": 0]),
      ("xbox.gip", ["usbStartupRetryDelayMs": 60_001]),
      ("xbox.gip", ["usbTransferTimeoutMs": 0]),
      ("xbox.gip", ["usbTransferTimeoutMs": 60_001]),
      ("xbox.gip", ["frameQueueCapacity": 0]),
      ("hid.descriptor", ["frameQueueCapacity": 1_025]),
      ("sony.dualsense", ["frameQueueCapacity": 1.5]),
    ] as [(String, [String: any Sendable])]
  )
  func rejectsTuningOutOfRangeOrOutsideItsFamily(family: String, tuning: [String: any Sendable]) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": family], extra: ["tuning": tuning])
    }
  }

  @Test(arguments: ["nintendo.switch2", "nintendo.switch-input-only"])
  func rejectsRecoveryTuningForSwitchDriversWithoutRecovery(family: String) throws {
    _ = try decode(protocol: ["family": family])
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: ["family": family],
        extra: ["tuning": ["hidStartupRecoveryRounds": 2]]
      )
    }
  }

  static let vibrationUUID = "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149"
  static let switch2: [String: any Sendable] = [
    "family": "nintendo.switch2"
  ]

  @Test
  func decodesTheBluetoothLEVibrationCharacteristicOfASwitch2Controller() throws {
    let document = try decode(
      protocol: Self.switch2,
      extra: ["bluetoothLE": ["vibrationCharacteristic": Self.vibrationUUID]]
    )
    #expect(document.bluetoothLE?.vibrationCharacteristic == Self.vibrationUUID)
    #expect(
      try DeviceCatalog.makeRuntimeProfile(document).bluetoothLEVibrationCharacteristic
        == Self.vibrationUUID
    )
  }

  @Test(
    arguments: [
      (["family": "nintendo.switch1"], ["vibrationCharacteristic": vibrationUUID]),
      (["family": "sony.dualsense"], ["vibrationCharacteristic": vibrationUUID]),
      (switch2, ["vibrationCharacteristic": vibrationUUID.lowercased()]),
      (switch2, ["vibrationCharacteristic": "FA19B0FB"]),
      (switch2, [:]),
      (switch2, ["vibrationCharacteristic": vibrationUUID, "service": vibrationUUID]),
    ] as [([String: any Sendable], [String: any Sendable])]
  )
  func rejectsBluetoothLEOutsideSwitch2OrMalformed(
    protocolInfo: [String: any Sendable],
    bluetoothLE: [String: any Sendable]
  ) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: protocolInfo, extra: ["bluetoothLE": bluetoothLE])
    }
  }

  private static func controllerSchema() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent("Resources/Schemas/controller.schema.json")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private static func enumValues(_ node: Any?) -> [String]? {
    (node as? [String: Any])?["enum"] as? [String]
  }

  /// The Swift value spellings of each enumerated parameter, in declaration order.
  private static let parameterEnums: [String: [String]] = [
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

  /// The families a branch's condition selects with `const` or `enum`.
  private static func familyNames(_ branch: [String: Any]) -> [String] {
    let condition = branch["if"] as? [String: Any]
    let properties = condition?["properties"] as? [String: Any]
    let family = properties?["family"] as? [String: Any]
    if let name = family?["const"] as? String { return [name] }
    return family?["enum"] as? [String] ?? []
  }

  private func decode(
    protocol protocolInfo: [String: any Sendable],
    usb: [String: any Sendable]? = nil,
    capabilities: [String: any Sendable]? = nil,
    extra: [String: any Sendable] = [:],
    vendorID: Int = 0x045E
  ) throws -> ControllerRecordDocument {
    var record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": vendorID, "productID": 0x02EA,
      "modes": [["id": "default", "protocol": protocolInfo]],
    ]
    record.merge(extra) { current, _ in current }
    record["usb"] = usb
    record["capabilities"] = capabilities
    return try JSONDecoder().decode(
      ControllerRecordDocument.self,
      from: JSONSerialization.data(withJSONObject: record)
    )
  }
}
