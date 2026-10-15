import Foundation

/// Strict runtime representation of the one current controller-record contract.
///
/// JSONDecoder normally ignores unknown keys. This decoder instead rejects
/// removed or misspelled fields and requires the `apiVersion` and `kind` of the controller
/// contract.
struct ControllerRecordDocument: Decodable {
  /// The `kind` of a controller record.
  static let kind = "Controller"

  let vendorID: Int
  let productID: Int
  let protocolInfo: ProtocolInfo
  /// Alternative modes of an HID controller, tried in order; empty when the record has none. The
  /// record's own protocol is the default mode.
  let modes: [ModeDocument]
  let usb: USBOverride?
  /// Present exactly for Switch 2 controllers that connect over Bluetooth LE.
  let bluetoothLE: BluetoothLE?
  let capabilities: ControllerCapabilityDelta
  /// Nil leaves a controller macOS supports to macOS.
  let server: ControllerServer?
  /// Set only on raw-USB records that OJD's USB extension serves.
  let route: ControllerRecordRoute?
  let rumbleTemplate: RumbleOutputTemplate?
  /// Fixed reports OJD sends when it starts the controller; empty when the record has none.
  let startupWrites: [RecordStartupWrite]
  /// Fixed raw-USB packets OJD sends when it starts the controller; empty when the record has
  /// none. Only a family whose description carries raw-USB startup packets takes them.
  let usbStartupWrites: [USBStartupWrite]
  /// Present exactly for the `hid.report-layout` family.
  let inputLayout: ControllerInputLayout?
  /// Present only for the `hid.descriptor` family, which then replaces the description's map.
  let hidUsageMap: HIDUsageMap?
  let tuning: ControllerTuning

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: [
      "apiVersion", "kind", "vendorID", "productID", "protocol", "modes", "usb",
      "bluetoothLE", "capabilities", "server", "route", "output", "input", "tuning",
    ])
    let apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
    let kind = try container.decodeOptional(String.self, for: "kind")
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: apiVersion,
      kind: kind,
      expected: Self.kind
    ) {
      if problem.code != nil { throw problem }
      throw DecodingError.dataCorruptedError(
        forKey: DocumentKey("kind"),
        in: container,
        debugDescription: problem.message
      )
    }
    vendorID = try container.decode(Int.self, for: "vendorID")
    productID = try container.decode(Int.self, for: "productID")
    protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
    modes = try container.decodeOptional([ModeDocument].self, for: "modes") ?? []
    if container.contains(DocumentKey("modes")), modes.isEmpty {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey("modes")],
          debugDescription: "modes must not be empty"
        )
      )
    }
    usb = try container.decodeOptional(USBOverride.self, for: "usb")
    bluetoothLE = try container.decodeOptional(BluetoothLE.self, for: "bluetoothLE")
    capabilities =
      try container.decodeOptional(CapabilityDelta.self, for: "capabilities")?.delta ?? .none
    server = try container.decodeOptional(String.self, for: "server").map { name in
      guard let server = ControllerServer(rawValue: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: DocumentKey("server"),
          in: container,
          debugDescription: "server must be system or ojd"
        )
      }
      return server
    }
    route = try container.decodeOptional(String.self, for: "route").map { name in
      guard let route = ControllerRecordRoute(rawValue: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: DocumentKey("route"),
          in: container,
          debugDescription: "route must be ExtensionOwned"
        )
      }
      return route
    }
    let output = try container.decodeOptional(Output.self, for: "output")
    rumbleTemplate = output?.rumble
    startupWrites = output?.startup ?? []
    usbStartupWrites = output?.usbStartup ?? []
    let input = try container.decodeOptional(Input.self, for: "input")
    inputLayout = input?.layout
    hidUsageMap = input?.usageMap
    guard input?.shapes.isEmpty ?? true else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey("input")],
          debugDescription: "descriptorShapes belong to a protocol description"
        )
      )
    }
    tuning = try container.decodeOptional(Tuning.self, for: "tuning")?.tuning ?? .none
    try validateOwnershipAndOutput(codingPath: decoder.codingPath)
    try validateTuning(codingPath: decoder.codingPath)
    try validateBluetoothLE(codingPath: decoder.codingPath)
    guard capabilitiesAreDeclared(by: protocolInfo.protocolID) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey("capabilities")],
          debugDescription: "capabilities must be deltas their driver declares"
        )
      )
    }
    try validateModes(codingPath: decoder.codingPath)
    if let endpoints = usb?.endpoints {
      let defaultEndpoints = protocolInfo.protocolID.protocolDescription.endpoints
      guard (endpoints.input, endpoints.output) != (defaultEndpoints.input, defaultEndpoints.output)
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("usb"), DocumentKey("endpoints")],
            debugDescription: "protocol-default endpoints must be omitted"
          )
        )
      }
    }
  }

  /// Only the deltas the family's description declares have a driver that acts on them.
  func capabilitiesAreDeclared(by protocolID: PhysicalProtocolID) -> Bool {
    protocolID.protocolDescription.recordCapabilities.permits(capabilities)
  }

  /// macOS cannot serve a raw-USB family, HID startup writes go to HID controllers while raw-USB
  /// startup packets go to families that read them, only a driver that encodes rumble from a
  /// template may name one, and the report-layout family alone has, and needs, an input layout.
  private func validateOwnershipAndOutput(codingPath: [any CodingKey]) throws {
    let rawUSB = protocolInfo.protocolID.usesRawUSB(storedVariant: protocolInfo.protocolVariant)
    if server != nil, rawUSB {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("server")],
          debugDescription: "server applies only to HID controllers"
        )
      )
    }
    if route != nil, !rawUSB {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("route")],
          debugDescription: "route ExtensionOwned applies only to raw-USB controllers"
        )
      )
    }
    if !startupWrites.isEmpty, rawUSB {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("output"), DocumentKey("startup")],
          debugDescription: "HID startup writes apply only to HID controllers"
        )
      )
    }
    if !usbStartupWrites.isEmpty {
      let carriesUSBWrites =
        ProtocolDescription.bundled[protocolInfo.protocolID]?.usbStartupWrites.isEmpty == false
      guard carriesUSBWrites, protocolInfo.initialization == nil else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: codingPath + [DocumentKey("output"), DocumentKey("startup")],
            debugDescription:
              "raw-USB startup writes need a family that reads them and no initialization list"
          )
        )
      }
    }
    if (inputLayout != nil) != protocolInfo.protocolID.requiresRecordInputLayout {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("input")],
          debugDescription: "an input layout is required for hid.report-layout and only there"
        )
      )
    }
    if hidUsageMap != nil, protocolInfo.protocolID != .hidDescriptor {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("input")],
          debugDescription: "a HID usage map applies only to hid.descriptor"
        )
      )
    }
    if rumbleTemplate != nil, !protocolInfo.protocolID.encodesRumbleTemplate {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("output"), DocumentKey("rumble")],
          debugDescription: "rumble templates require a driver that encodes them"
        )
      )
    }
  }

  struct RumbleTemplate: Decodable {
    let template: RumbleOutputTemplate

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let motors = RumbleOutputTemplate.templateMotors
      try container.rejectUnknown(allowed: Set(["report"] + motors.map(\.rawValue)))
      let report = try container.decode(TemplateReport.self, for: "report").report
      var motorBytes: [PhysicalRumbleMotor: Int] = [:]
      for motor in motors {
        motorBytes[motor] = try container.decodeOptional(TemplateByte.self, for: motor.rawValue)?
          .byte
      }
      do {
        template = try RumbleOutputTemplate(report: report, motorBytes: motorBytes)
      } catch {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: error.description)
        )
      }
    }
  }

  struct TemplateReport: Decodable {
    let report: ControllerTemplateReport

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["kind", "id", "length"])
      let kind = try container.decode(String.self, for: "kind")
      let reportID = try container.decode(Int.self, for: "id")
      let length = try container.decode(Int.self, for: "length")
      guard kind == "output" || kind == "feature", let id = UInt8(exactly: reportID) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "report must be an output or feature report with ID 0...255"
          )
        )
      }
      report = ControllerTemplateReport(
        kind: kind == "output" ? .output : .feature,
        reportID: id,
        length: length
      )
    }
  }

  struct TemplateByte: Decodable {
    let byte: Int

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte"])
      byte = try container.decode(Int.self, for: "byte")
    }
  }

  struct ProtocolInfo: Decodable {
    let protocolID: PhysicalProtocolID
    /// Nil unless the family stores its variant (``PhysicalProtocolID/storesVariant``).
    let protocolVariant: PhysicalProtocolVariantID?
    let parameters: ProtocolParameters
    /// Named GIP initialization actions; nil selects the driver's default sequence.
    let initialization: [String]?
    let keepAliveEnabled: Bool?
    /// The named assembly policy; its vocabulary is empty, so every name fails.
    let assembly: ControllerAssemblyPolicy?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "family", "variant", "parameters", "initialization", "keepAlive", "assembly",
      ])
      let family = try container.decode(String.self, for: "family")
      let variantName = try container.decodeOptional(String.self, for: "variant")
      guard let protocolID = PhysicalProtocolID(rawValue: family) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "unknown family \(family)")
        )
      }
      let variant = variantName.flatMap(PhysicalProtocolVariantID.init(rawValue:))
      // Only families whose variant transport cannot decide store it, and it must be theirs.
      guard protocolID.storesVariant == (variantName != nil),
        variantName == nil || variant.map(protocolID.variants.contains) == true
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "variant must be a stored variant of family \(family)"
          )
        )
      }
      self.protocolID = protocolID
      protocolVariant = variant
      parameters = try container.decodeOptional(ProtocolParameters.self, for: "parameters") ?? .none
      initialization = try container.decodeNamedPacketList(of: protocolID, for: "initialization")
      keepAliveEnabled = try container.decodeOptional(Bool.self, for: "keepAlive")
      if let name = try container.decodeOptional(String.self, for: "assembly") {
        guard let policy = ControllerAssemblyPolicy(name: name) else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown assembly \(name)")
          )
        }
        assembly = policy
      } else {
        assembly = nil
      }
      try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
      let violation: String? =
        if let problem = parameters.violation(family: protocolID, variant: protocolVariant) {
          problem
        } else if initialization != nil && protocolID != .xboxGIP {
          "initialization actions must be declared by the selected driver"
        } else if keepAliveEnabled != nil && protocolID != .xboxGIP {
          "keep-alive policy requires the GIP driver"
        } else { nil }
      if let violation {
        throw DecodingError.dataCorrupted(
          .init(codingPath: codingPath, debugDescription: violation)
        )
      }
    }
  }

  /// Capability corrections against the bound parser's declared defaults.
  struct CapabilityDelta: Decodable {
    let delta: ControllerCapabilityDelta

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["absent", "present", "rumble"])
      let absent = Set(try container.decodeUniqueList(Control.self, for: "absent") ?? [])
      let present = Set(try container.decodeUniqueList(Control.self, for: "present") ?? [])
      let rumble = try container.decodeOptional(String.self, for: "rumble")
      guard !container.allKeys.isEmpty, absent.isDisjoint(with: present),
        rumble == nil || rumble == "absent"
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "capabilities must be nonempty, disjoint, and declare rumble only as absent"
          )
        )
      }
      delta = ControllerCapabilityDelta(
        absentControls: absent,
        presentControls: present,
        rumbleAbsent: rumble != nil
      )
    }
  }

  struct USBOverride: Decodable {
    let configuration: String?
    let postHandshakeSettleMilliseconds: Int?
    let endpoints: Endpoints?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["configuration", "postHandshakeSettleMs", "endpoints"])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "usb must not be empty")
        )
      }
      configuration = try container.decodeOptional(String.self, for: "configuration")
      postHandshakeSettleMilliseconds = try container.decodeOptional(
        Int.self,
        for: "postHandshakeSettleMs"
      )
      endpoints = try container.decodeOptional(Endpoints.self, for: "endpoints")
      guard postHandshakeSettleMilliseconds.map({ (1...60_000).contains($0) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("postHandshakeSettleMs")],
            debugDescription: "postHandshakeSettleMs must be in 1...60000"
          )
        )
      }
    }
  }

  struct Endpoints: Decodable {
    let input: Int
    let output: Int

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["in", "out"])
      input = try container.decode(Int.self, for: "in")
      output = try container.decode(Int.self, for: "out")
      guard DeviceTransportProfile.inputEndpointRange.contains(input),
        DeviceTransportProfile.outputEndpointRange.contains(output)
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "endpoints must use IN 128...255 and OUT 1...127"
          )
        )
      }
    }
  }
}

/// A coding key for any field name, so the strict decoders can name and reject fields.
struct DocumentKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int? = nil

  init(_ value: String) { stringValue = value }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { self.init(String(intValue)) }
}

extension KeyedDecodingContainer where Key == DocumentKey {
  func decode<T: Decodable>(_ type: T.Type, for key: String) throws -> T {
    try decode(type, forKey: DocumentKey(key))
  }

  func decodeOptional<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
    let codingKey = DocumentKey(key)
    guard contains(codingKey) else { return nil }
    guard try !decodeNil(forKey: codingKey) else {
      throw DecodingError.valueNotFound(
        type,
        .init(codingPath: codingPath + [codingKey], debugDescription: "null is not permitted")
      )
    }
    return try decode(type, forKey: codingKey)
  }

  /// Decodes a nonempty list of unique current identifiers; unknown values fail.
  func decodeUniqueList<Value: RawRepresentable & Hashable>(
    _ type: Value.Type,
    for key: String
  ) throws -> [Value]? where Value.RawValue == String {
    guard let names = try decodeOptional([String].self, for: key) else { return nil }
    let values = names.compactMap(Value.init(rawValue:))
    guard !values.isEmpty, values.count == names.count, Set(values).count == values.count else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must contain unique, current, nonempty values"
        )
      )
    }
    return values
  }

  /// Decodes a nonempty list of unique ids of named packets that `family`'s description defines;
  /// any other id fails.
  func decodeNamedPacketList(of family: PhysicalProtocolID, for key: String) throws -> [String]? {
    guard let names = try decodeOptional([String].self, for: key) else { return nil }
    let plan = ProtocolDescription.bundled[family]?.namedPackets
    guard !names.isEmpty, Set(names).count == names.count,
      names.allSatisfy({ plan?.packet(named: $0) != nil })
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must contain unique, nonempty ids of the family's named packets"
        )
      )
    }
    return names
  }

  func rejectUnknown(allowed: Set<String>) throws {
    let unknown = Set(allKeys.map(\.stringValue)).subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath,
          debugDescription: "unknown field(s): \(unknown.joined(separator: ", "))"
        )
      )
    }
  }
}
