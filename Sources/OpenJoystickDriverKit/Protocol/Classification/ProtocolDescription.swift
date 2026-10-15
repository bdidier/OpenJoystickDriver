import Foundation

/// Why a protocol description is invalid, in words for the person who wrote it, with the
/// catalog code that names the failure.
struct ProtocolDescriptionProblem: Error, Equatable, Sendable, CustomStringConvertible {
  let code: ErrorCode
  let detail: String

  init(_ code: ErrorCode, _ detail: String) {
    self.code = code
    self.detail = detail
  }

  var description: String { "\(code.rawValue): \(detail)" }
}

/// One family's protocol description (`Resources/Protocols/<family>.json`): the interface
/// signatures that bind its variants, the typed parameters its records may set, the facts its
/// driver reads (endpoints, raw USB, record sections, tuning keys, button labels, what OJD still
/// sends when macOS serves the controller), and the defaults its records layer over. Drivers read
/// these values; they hold no copy.
struct ProtocolDescription: Sendable {
  /// A parameter's declared type.
  enum ParameterType: Equatable, Sendable {
    /// `true` or absent.
    case flag
    /// One of these names.
    case enumeration([String])
    /// An object of integer fields, each within its range.
    case object([String: ClosedRange<Int>])
  }

  /// The default USB endpoint addresses of a raw-USB family.
  struct Endpoints: Equatable, Sendable {
    let input: Int
    let output: Int
  }

  /// Which variants of a family are reached through raw USB.
  enum RawUSB: Equatable, Sendable {
    case never
    case always
    case variants(Set<PhysicalProtocolVariantID>)

    func applies(to variant: PhysicalProtocolVariantID?) -> Bool {
      switch self {
      case .never: false
      case .always: true
      case .variants(let variants): variant.map(variants.contains) ?? false
      }
    }
  }

  /// A record section whose layout the family's driver reads.
  enum RecordSection: String, Sendable {
    case input
    case rumble
  }

  /// The `kind` of a protocol description.
  static let kind = "ProtocolDescription"

  let family: PhysicalProtocolID
  let endpoints: Endpoints
  let rawUSB: RawUSB
  let recordSections: Set<RecordSection>
  /// The `tuning` keys the family reads beyond `stickDeadzone`; none for a raw-USB variant.
  let tuningKeys: Set<ControllerTuning.Key>
  let buttonLabels: ControllerButtonLabels
  /// What OJD still sends when macOS serves the controller.
  let macOSOwnedOutput: MacOSOwnedOutput
  let interfaceSignatures: [ProtocolInterfaceSignature]
  /// The parameters records of this family may set, by name.
  let parameters: [String: ParameterType]
  let capabilities: ControllerCapabilityDelta?
  let rumbleTemplate: RumbleOutputTemplate?
  /// The family's initialization sequence: writes sent when a HID controller starts.
  let startupWrites: [RecordStartupWrite]
  let inputLayout: ControllerInputLayout?
  let tuning: ControllerTuning?

  /// The bundled descriptions, by family.
  static let bundled: [PhysicalProtocolID: Self] = {
    do { return try loadBundled() } catch {
      fatalError("[ProtocolDescription] Invalid protocol descriptions: \(error)")
    }
  }()

  private static func loadBundled() throws -> [PhysicalProtocolID: Self] {
    var descriptions: [PhysicalProtocolID: Self] = [:]
    for protocolID in PhysicalProtocolID.allCases {
      guard let url = Bundle.module.url(forResource: protocolID.rawValue, withExtension: "json")
      else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(protocolID.rawValue).json is missing from the bundle"
        )
      }
      descriptions[protocolID] = try decode(
        Data(contentsOf: url),
        protocolID: protocolID,
        fileName: url.lastPathComponent
      )
    }
    return descriptions
  }

  /// Decodes one description, the file `fileName` that the bundle holds for `protocolID`.
  ///
  /// A malformed document, an unknown field and a value outside its range are E5002; a family
  /// that is not the file's is E5003; a variant that the family lacks is E5004.
  static func decode(
    _ data: Data,
    protocolID: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> Self {
    let document: Document
    do {
      document = try JSONDecoder().decode(Document.self, from: data)
    } catch {
      throw ProtocolDescriptionProblem(.invalidProtocolDescription, "\(fileName): \(error)")
    }
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: document.apiVersion,
      kind: document.kind,
      expected: kind
    ) {
      throw ProtocolDescriptionProblem(
        problem.code ?? .invalidProtocolDescription,
        "\(fileName): \(problem.message)"
      )
    }
    guard document.family == protocolID.rawValue else {
      throw ProtocolDescriptionProblem(
        .protocolDescriptionFamilyMismatch,
        "\(fileName): family must be \(protocolID.rawValue)"
      )
    }
    var signatures: [ProtocolInterfaceSignature] = []
    for signature in document.interfaceSignatures {
      guard let variant = PhysicalProtocolVariantID(rawValue: signature.variant),
        protocolID.variants.contains(variant)
      else {
        throw ProtocolDescriptionProblem(
          .unknownProtocolVariant,
          "\(fileName): \(protocolID.rawValue) has no variant \(signature.variant)"
        )
      }
      signatures.append(
        ProtocolInterfaceSignature(
          protocolID: protocolID,
          variant: variant,
          interfaceClass: signature.interfaceClass,
          interfaceSubclass: signature.interfaceSubclass,
          interfaceProtocol: signature.interfaceProtocol,
          requiredInterfaceNumber: signature.interfaceNumber
        )
      )
    }
    var rawUSB = RawUSB.never
    switch document.rawUSB {
    case .none: break
    case .always: rawUSB = .always
    case .variants(let names):
      var variants: Set<PhysicalProtocolVariantID> = []
      for name in names {
        guard let variant = PhysicalProtocolVariantID(rawValue: name),
          protocolID.variants.contains(variant)
        else {
          throw ProtocolDescriptionProblem(
            .unknownProtocolVariant,
            "\(fileName): \(protocolID.rawValue) has no variant \(name)"
          )
        }
        variants.insert(variant)
      }
      rawUSB = .variants(variants)
    }
    let description = Self(
      family: protocolID,
      endpoints: document.endpoints,
      rawUSB: rawUSB,
      recordSections: document.recordSections,
      tuningKeys: document.tuningKeys,
      buttonLabels: document.buttonLabels,
      macOSOwnedOutput: document.macOSOwnedOutput,
      interfaceSignatures: signatures,
      parameters: document.parameters,
      capabilities: document.defaults?.capabilities,
      rumbleTemplate: document.defaults?.output?.rumble,
      startupWrites: document.defaults?.output?.startup ?? [],
      inputLayout: document.defaults?.input,
      tuning: document.defaults?.tuning
    )
    if let violation = description.scopeViolation {
      throw ProtocolDescriptionProblem(.invalidProtocolDescription, "\(fileName): \(violation)")
    }
    return description
  }

  /// Why the defaults name something the family's driver does not read, or nil. The rule reads
  /// only this description, so it holds while the bundle is still loading.
  private var scopeViolation: String? {
    if inputLayout != nil, !recordSections.contains(.input) {
      return "an input layout applies only to a family that reads one"
    }
    if rumbleTemplate != nil, !recordSections.contains(.rumble) {
      return "rumble templates require a driver that encodes them"
    }
    if !startupWrites.isEmpty, rawUSB == .always {
      return "startup writes apply only to HID controllers"
    }
    if let tuning {
      let scope = Self.tuningScope(tuningKeys: tuningKeys, rawUSB: rawUSB, variant: nil)
      for key in ControllerTuning.Key.allCases
      where tuning.setKeys.contains(key) && !scope.contains(key) {
        return "\(key) is not read by the \(family.rawValue) driver"
      }
    }
    return nil
  }

  /// The tuning keys a controller of this family and stored variant reads: `stickDeadzone`, and
  /// the family's `tuningKeys` unless the controller is reached through raw USB.
  static func tuningScope(
    tuningKeys: Set<ControllerTuning.Key>,
    rawUSB: RawUSB,
    variant: PhysicalProtocolVariantID?
  ) -> Set<ControllerTuning.Key> {
    rawUSB.applies(to: variant) ? [.stickDeadzone] : tuningKeys.union([.stickDeadzone])
  }

  private struct Document: Decodable {
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
      let capabilities: ControllerCapabilityDelta?
      let output: ControllerRecordDocument.Output?
      let input: ControllerInputLayout?
      let tuning: ControllerTuning?

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["capabilities", "output", "input", "tuning"])
        guard !container.allKeys.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "defaults must not be empty")
          )
        }
        capabilities = try container.decodeOptional(
          ControllerRecordDocument.CapabilityDelta.self,
          for: "capabilities"
        )?.delta
        output = try container.decodeOptional(ControllerRecordDocument.Output.self, for: "output")
        input = try container.decodeOptional(
          ControllerRecordDocument.InputLayout.self,
          for: "input"
        )?.layout
        tuning = try container.decodeOptional(ControllerRecordDocument.Tuning.self, for: "tuning")?
          .tuning
      }
    }

    let apiVersion: String?
    let kind: String?
    let family: String
    let endpoints: Endpoints
    let rawUSB: RawUSBDeclaration?
    let recordSections: Set<RecordSection>
    let tuningKeys: Set<ControllerTuning.Key>
    let buttonLabels: ControllerButtonLabels
    let macOSOwnedOutput: MacOSOwnedOutput
    let interfaceSignatures: [Signature]
    let parameters: [String: ParameterType]
    let defaults: Defaults?

    /// A unique, nonempty list of `Element` names as a set; empty when absent.
    private static func decodeSet<Element: RawRepresentable & Hashable>(
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
        "buttonLabels", "macOSOwnedOutput", "interfaceSignatures", "parameters", "defaults",
      ])
      apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
      kind = try container.decodeOptional(String.self, for: "kind")
      family = try container.decode(String.self, for: "family")
      endpoints = try container.decode(EndpointsDocument.self, for: "endpoints").endpoints
      rawUSB = try container.decodeOptional(RawUSBDeclaration.self, for: "rawUSB")
      recordSections = try Self.decodeSet(RecordSection.self, "recordSections", container)
      tuningKeys = try Self.decodeSet(ControllerTuning.Key.self, "tuningKeys", container)
      guard !tuningKeys.contains(.stickDeadzone) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("tuningKeys")],
            debugDescription: "stickDeadzone is read by every driver"
          )
        )
      }
      switch try container.decodeOptional(String.self, for: "buttonLabels") {
      case nil: buttonLabels = .standard
      case "PlayStation": buttonLabels = .playStation
      case "Nintendo": buttonLabels = .nintendo
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("buttonLabels")],
            debugDescription: "buttonLabels is PlayStation or Nintendo"
          )
        )
      }
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
  private struct EndpointsDocument: Decodable {
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
  private enum RawUSBDeclaration: Decodable {
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

  /// `macOSOwnedOutput`: lighting, rumble and reports OJD still sends to a controller macOS serves.
  private struct MacOSOwnedOutputDocument: Decodable {
    let value: MacOSOwnedOutput

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "lightingFeatures", "drivesRumble", "reports", "setsStartupPlayerIndicator",
        "readsStartupFeatures",
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
          ?? false
      )
    }
  }

  /// A parameter declaration: `{type: flag}`, `{type: enum, values}` or `{type: object, fields}`.
  private struct Declaration: Decodable {
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

  private struct IntegerField: Decodable {
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
