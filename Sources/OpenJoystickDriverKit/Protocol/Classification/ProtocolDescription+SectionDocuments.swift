import Foundation

/// The documents of the description sections a family may declare: endpoints, raw USB,
/// controls, record capabilities, macOS-owned output, parameter declarations and integer fields.
extension ProtocolDescription {
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
        guard base == "Xbox" else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("base")],
              debugDescription: "base is Xbox"
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

  /// A parameter declaration: `{type: Flag}`, `{type: Enum, values}` or `{type: Object, fields}`.
  struct Declaration: Decodable {
    let type: ParameterType

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let name = try container.decode(String.self, for: "type")
      switch name {
      case "Flag":
        try container.rejectUnknown(allowed: ["type"])
        type = .flag
      case "Enum":
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
      case "Object":
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
            debugDescription: "type is Flag, Enum or Object"
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
      guard try container.decode(String.self, for: "type") == "Integer" else {
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
