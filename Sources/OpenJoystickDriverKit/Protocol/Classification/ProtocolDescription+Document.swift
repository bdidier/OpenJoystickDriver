import Foundation

extension ProtocolDescription {
  struct Document: Decodable {
    struct Signature: Decodable {
      let variant: String
      let interfaceClass: UInt8
      let interfaceSubclass: UInt8
      let interfaceProtocol: UInt8
      let interfaceNumber: UInt8?

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: [
          "variant", "interfaceClass", "interfaceSubclass", "interfaceProtocol", "interfaceNumber",
        ])
        variant = try container.decode(String.self, for: "variant")
        interfaceClass = try container.decode(UInt8.self, for: "interfaceClass")
        interfaceSubclass = try container.decode(UInt8.self, for: "interfaceSubclass")
        interfaceProtocol = try container.decode(UInt8.self, for: "interfaceProtocol")
        interfaceNumber = try container.decodeOptional(UInt8.self, for: "interfaceNumber")
      }
    }

    struct Defaults: Decodable {
      let output: ControllerRecordDocument.Output?
      let session: Session?
      let input: ControllerRecordDocument.Input?
      let tuning: ControllerTuning?
      /// Defaults by variant name, layered over `tuning` for that variant.
      let variantTuning: [String: ControllerTuning]

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: [
          "output", "session", "input", "tuning", "variants",
        ])
        guard !container.allKeys.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "defaults must not be empty")
          )
        }
        output = try container.decodeOptional(ControllerRecordDocument.Output.self, for: "output")
        session = try container.decodeOptional(Session.self, for: "session")
        input = try container.decodeOptional(ControllerRecordDocument.Input.self, for: "input")
        tuning = try container.decodeOptional(ControllerRecordDocument.Tuning.self, for: "tuning")?
          .tuning
        let variants = try container.decodeOptional([String: VariantDefaults].self, for: "variants")
        guard variants?.isEmpty != true else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("variants")],
              debugDescription: "variants must not be empty"
            )
          )
        }
        variantTuning = variants?.mapValues(\.tuning) ?? [:]
      }
    }

    /// `defaults.session`: what runs while the device is open. Today the keep-alive and the
    /// Switch 1 subcommands; task 11.4 moves the startup writes here, so all share one `session`
    /// shape.
    struct Session: Decodable {
      let keepAlive: KeepAlive?
      let subcommands: SubcommandPlan?

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["keepAlive", "subcommands"])
        guard !container.allKeys.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "session must not be empty")
          )
        }
        keepAlive = try container.decodeOptional(KeepAlive.self, for: "keepAlive")
        subcommands = try container.decodeOptional(SubcommandPlan.self, for: "subcommands")
      }
    }

    /// `defaults.variants.<variant>`: the tuning that a variant starts from.
    struct VariantDefaults: Decodable {
      let tuning: ControllerTuning

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["tuning"])
        tuning = try container.decode(ControllerRecordDocument.Tuning.self, for: "tuning").tuning
      }
    }

    let apiVersion: String?
    let kind: String?
    let family: String
    let endpoints: Endpoints
    let rawUSB: RawUSBDeclaration?
    let recordSections: Set<RecordSection>
    let tuningKeys: Set<ControllerTuning.Key>
    let rawUSBTuningKeys: Set<ControllerTuning.Key>
    let controls: ControllerCapabilities?
    let recordCapabilities: RecordCapabilityRules
    let macOSOwnedOutput: MacOSOwnedOutput
    let interfaceSignatures: [Signature]
    let parameters: [String: ParameterType]
    let defaults: Defaults?

    /// A unique, nonempty list of `Element` names as a set; empty when absent.
    static func decodeSet<Element: RawRepresentable & Hashable>(
      _: Element.Type,
      _ key: String,
      _ container: KeyedDecodingContainer<DocumentKey>
    ) throws -> Set<Element> where Element.RawValue == String {
      guard let names = try container.decodeOptional([String].self, for: key) else { return [] }
      let elements = names.compactMap(Element.init(rawValue:))
      guard !names.isEmpty, elements.count == names.count, Set(elements).count == names.count else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: container.codingPath + [DocumentKey(key)],
            debugDescription: "\(key) lists unique, known names"
          )
        )
      }
      return Set(elements)
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "apiVersion", "kind", "family", "endpoints", "rawUSB", "recordSections", "tuningKeys",
        "rawUSBTuningKeys", "controls", "recordCapabilities", "macOSOwnedOutput",
        "interfaceSignatures", "parameters", "defaults",
      ])
      apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
      kind = try container.decodeOptional(String.self, for: "kind")
      family = try container.decode(String.self, for: "family")
      endpoints = try container.decode(EndpointsDocument.self, for: "endpoints").endpoints
      rawUSB = try container.decodeOptional(RawUSBDeclaration.self, for: "rawUSB")
      recordSections = try Self.decodeSet(RecordSection.self, "recordSections", container)
      tuningKeys = try Self.decodeSet(ControllerTuning.Key.self, "tuningKeys", container)
      rawUSBTuningKeys = try Self.decodeSet(
        ControllerTuning.Key.self,
        "rawUSBTuningKeys",
        container
      )
      guard !tuningKeys.contains(.stickDeadzone), !rawUSBTuningKeys.contains(.stickDeadzone) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("tuningKeys")],
            debugDescription: "stickDeadzone is read by every driver"
          )
        )
      }
      controls = try container.decodeOptional(ControlsDocument.self, for: "controls")?.value
      recordCapabilities =
        try container.decodeOptional(RecordCapabilitiesDocument.self, for: "recordCapabilities")?
        .value ?? .none
      macOSOwnedOutput =
        try container.decodeOptional(MacOSOwnedOutputDocument.self, for: "macOSOwnedOutput")?.value
        ?? .none
      let signatures = try container.decodeOptional([Signature].self, for: "interfaceSignatures")
      guard signatures?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("interfaceSignatures")],
            debugDescription: "interfaceSignatures must not be empty"
          )
        )
      }
      interfaceSignatures = signatures ?? []
      let declarations = try container.decodeOptional([String: Declaration].self, for: "parameters")
      guard declarations?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("parameters")],
            debugDescription: "parameters must not be empty"
          )
        )
      }
      let unknown = Set(declarations.map { Array($0.keys) } ?? []).subtracting(
        ProtocolParameters.names
      )
      guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("parameters")],
            debugDescription:
              "no driver reads parameter(s): \(unknown.sorted().joined(separator: ", "))"
          )
        )
      }
      parameters = declarations?.mapValues(\.type) ?? [:]
      defaults = try container.decodeOptional(Defaults.self, for: "defaults")
    }
  }

  /// `endpoints`: the default input and output endpoint addresses.
  struct EndpointsDocument: Decodable {
    let endpoints: Endpoints

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["in", "out"])
      let input = try container.decode(Int.self, for: "in")
      let output = try container.decode(Int.self, for: "out")
      guard (0...255).contains(input), (0...255).contains(output) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "endpoints are 0...255")
        )
      }
      endpoints = Endpoints(input: input, output: output)
    }
  }

  /// `rawUSB`: `true` for every variant, or the variants that are raw USB.
  enum RawUSBDeclaration: Decodable {
    case always
    case variants([String])

    init(from decoder: any Decoder) throws {
      let single = try decoder.singleValueContainer()
      if let flag = try? single.decode(Bool.self) {
        guard flag else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "rawUSB is true or variants")
          )
        }
        self = .always
        return
      }
      let names = try single.decode([String].self)
      guard !names.isEmpty, Set(names).count == names.count else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "variants are unique, nonempty")
        )
      }
      self = .variants(names)
    }
  }

  /// `controls`: the controls every controller of the family has, as the Xbox layout with
  /// `remove` taken away and `add` put in, plus its digital triggers, touch contacts and motion.
  struct ControlsDocument: Decodable {
    let value: ControllerCapabilities

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "base", "remove", "add", "digitalTriggers", "touchContactCount", "motion",
      ])
      var controls: Set<Control> = []
      if let base = try container.decodeOptional(String.self, for: "base") {
        guard base == "xbox" else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("base")],
              debugDescription: "base is xbox"
            )
          )
        }
        controls = Control.xboxLayout
      }
      let remove = Set(try container.decodeUniqueList(Control.self, for: "remove") ?? [])
      let add = Set(try container.decodeUniqueList(Control.self, for: "add") ?? [])
      let digital = Set(try container.decodeUniqueList(Control.self, for: "digitalTriggers") ?? [])
      let touch = try container.decodeOptional(Int.self, for: "touchContactCount") ?? 0
      guard remove.isDisjoint(with: add), remove.isSubset(of: controls),
        digital.isSubset(of: [.leftTrigger, .rightTrigger]), (0...10).contains(touch),
        !controls.isEmpty || !add.isEmpty
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "controls remove only base controls, are disjoint, and name at least one control"
          )
        )
      }
      value = ControllerCapabilities(
        controls: controls.subtracting(remove).union(add),
        digitalTriggers: digital,
        touchContactCount: UInt8(touch),
        motion: try container.decodeOptional(Bool.self, for: "motion") ?? false
      )
    }
  }

  /// `recordCapabilities`: the capability deltas a record of the family may declare.
  struct RecordCapabilitiesDocument: Decodable {
    let value: RecordCapabilityRules

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["present", "rumbleAbsent"])
      let present = Set(try container.decodeUniqueList(Control.self, for: "present") ?? [])
      let rumbleAbsent = try container.decodeOptional(Bool.self, for: "rumbleAbsent") ?? false
      guard !container.allKeys.isEmpty, rumbleAbsent || container.contains(DocumentKey("present"))
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "recordCapabilities names a delta, and rumbleAbsent is true"
          )
        )
      }
      value = RecordCapabilityRules(presentControls: present, rumbleAbsent: rumbleAbsent)
    }
  }

  /// `macOSOwnedOutput`: lighting, rumble and reports OJD still sends to a controller macOS serves.
  struct MacOSOwnedOutputDocument: Decodable {
    let value: MacOSOwnedOutput

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "lightingFeatures", "drivesRumble", "reports", "setsStartupPlayerIndicator",
        "readsStartupFeatures", "rationale",
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "macOSOwnedOutput is not empty")
        )
      }
      var features: Set<PhysicalLightingFeature> = []
      for name in try container.decodeOptional([String].self, for: "lightingFeatures") ?? [] {
        guard let feature = PhysicalLightingFeature(rawValue: name) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("lightingFeatures")],
              debugDescription: "unknown lighting feature \(name)"
            )
          )
        }
        features.insert(feature)
      }
      let reports =
        try container.decodeOptional([ControllerRecordDocument.TemplateReport].self, for: "reports")
        ?? []
      value = MacOSOwnedOutput(
        lightingFeatures: features,
        drivesRumble: try container.decodeOptional(Bool.self, for: "drivesRumble") ?? false,
        reports: Set(reports.map(\.report)),
        setsStartupPlayerIndicator: try container.decodeOptional(
          Bool.self,
          for: "setsStartupPlayerIndicator"
        ) ?? false,
        readsStartupFeatures: try container.decodeOptional(Bool.self, for: "readsStartupFeatures")
          ?? false,
        rationale: try container.decodeOptional(String.self, for: "rationale")
      )
    }
  }

  /// A parameter declaration: `{type: flag}`, `{type: enum, values}` or `{type: object, fields}`.
  struct Declaration: Decodable {
    let type: ParameterType

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let name = try container.decode(String.self, for: "type")
      switch name {
      case "flag":
        try container.rejectUnknown(allowed: ["type"])
        type = .flag
      case "enum":
        try container.rejectUnknown(allowed: ["type", "values"])
        let values = try container.decode([String].self, for: "values")
        guard !values.isEmpty, Set(values).count == values.count,
          values.allSatisfy({ $0.first?.isUppercase == true })
        else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("values")],
              debugDescription: "values are unique, nonempty UpperCamelCase names"
            )
          )
        }
        type = .enumeration(values)
      case "object":
        try container.rejectUnknown(allowed: ["type", "fields"])
        let fields = try container.decode([String: IntegerField].self, for: "fields")
        guard !fields.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("fields")],
              debugDescription: "fields must not be empty"
            )
          )
        }
        type = .object(fields.mapValues(\.range))
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("type")],
            debugDescription: "type is flag, enum or object"
          )
        )
      }
    }
  }

  struct IntegerField: Decodable {
    let range: ClosedRange<Int>

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["type", "minimum", "maximum"])
      guard try container.decode(String.self, for: "type") == "integer" else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("type")],
            debugDescription: "an object field is an integer"
          )
        )
      }
      let minimum = try container.decode(Int.self, for: "minimum")
      let maximum = try container.decode(Int.self, for: "maximum")
      guard minimum <= maximum else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "minimum exceeds maximum")
        )
      }
      range = minimum...maximum
    }
  }
}
