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
/// signatures that bind its variants, the typed parameters its records may set, and the defaults
/// its records layer over. Drivers read these values; they hold no copy.
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

  /// The `kind` of a protocol description.
  static let kind = "ProtocolDescription"

  let family: PhysicalProtocolID
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
      else { continue }
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
    let description = Self(
      family: protocolID,
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

  /// Why the defaults name something the family's driver does not read, or nil.
  private var scopeViolation: String? {
    if inputLayout != nil, family != .hidReportLayout {
      return "an input layout applies only to hid.report-layout"
    }
    if rumbleTemplate != nil, !family.encodesRumbleTemplate {
      return "rumble templates require a driver that encodes them"
    }
    if !startupWrites.isEmpty, family.usesRawUSB(storedVariant: nil) {
      return "startup writes apply only to HID controllers"
    }
    if let tuning {
      let rawUSB = family.usesRawUSB(storedVariant: nil)
      for key in ControllerTuning.Key.allCases where tuning.setKeys.contains(key) {
        switch key {
        case .stickDeadzone: break
        case .inputLivenessTimeoutMs:
          if family != .sonyDualShock4 { return "\(key) requires the sony.dualshock4 family" }
        case .hidStartupRecoveryIntervalMs, .hidStartupRecoveryRounds:
          if family != .nintendoSwitch1 { return "\(key) requires the nintendo.switch1 family" }
        case .hidStartupIntervalMs, .minimumHIDOutputIntervalMs:
          if rawUSB { return "\(key) applies only to HID controllers" }
        }
      }
    }
    return nil
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
    let interfaceSignatures: [Signature]
    let parameters: [String: ParameterType]
    let defaults: Defaults?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "apiVersion", "kind", "family", "interfaceSignatures", "parameters", "defaults",
      ])
      apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
      kind = try container.decodeOptional(String.self, for: "kind")
      family = try container.decode(String.self, for: "family")
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
