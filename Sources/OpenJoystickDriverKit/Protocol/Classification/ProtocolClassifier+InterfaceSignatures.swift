import Foundation

/// A USB interface class, subclass and protocol triple that binds a family variant without a
/// catalog record, from the bundled protocol descriptions.
public struct ProtocolInterfaceSignature: Equatable, Sendable {
  public let protocolID: PhysicalProtocolID
  public let variant: PhysicalProtocolVariantID
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8
  public let interfaceProtocol: UInt8
  /// GIP shares its triple across interfaces; only this interface carries data.
  public let requiredInterfaceNumber: UInt8?

  /// The bundled signature of `protocolID`'s `variant`, or nil when it has none.
  public static func bundled(
    _ protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID
  ) -> Self? {
    ProtocolClassifier.signatures.first { $0.protocolID == protocolID && $0.variant == variant }
  }

  func matches(_ interface: PhysicalInterfaceSignature) -> Bool {
    interface.interfaceClass == interfaceClass && interface.interfaceSubclass == interfaceSubclass
      && interface.interfaceProtocol == interfaceProtocol
  }
}

extension ProtocolClassifier {
  typealias InterfaceSignature = ProtocolInterfaceSignature

  /// The `interfaceSignatures` of the bundled protocol descriptions (`Resources/Protocols/`),
  /// in family order. The Xbox triples are pinned against Linux `xpad.c` at the
  /// `ControllerSources.lock.json` commit: the `'X','B',0` table entry, `XPAD_XBOX360_VENDOR`
  /// (subclass 93, protocols 1 and 129), `XPAD_XBOXONE_VENDOR` (subclass 71, protocol 208), the
  /// GIP data interface number, and the interrupt IN+OUT endpoint requirement in `xpad_probe`.
  static let signatures: [InterfaceSignature] = {
    do { return try loadBundledSignatures() } catch {
      fatalError("[ProtocolClassifier] Invalid protocol descriptions: \(error)")
    }
  }()

  /// The `kind` of a protocol description.
  static let protocolDescriptionKind = "ProtocolDescription"

  private struct ProtocolDescriptionDocument: Decodable {
    struct Signature: Decodable {
      let variant: String
      let interfaceClass: UInt8
      let interfaceSubclass: UInt8
      let interfaceProtocol: UInt8
      let interfaceNumber: UInt8?

      enum CodingKeys: String, CodingKey, CaseIterable {
        case variant, interfaceClass, interfaceSubclass, interfaceProtocol, interfaceNumber
      }

      init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variant = try container.decode(String.self, forKey: .variant)
        interfaceClass = try container.decode(UInt8.self, forKey: .interfaceClass)
        interfaceSubclass = try container.decode(UInt8.self, forKey: .interfaceSubclass)
        interfaceProtocol = try container.decode(UInt8.self, forKey: .interfaceProtocol)
        interfaceNumber = try container.decodeIfPresent(UInt8.self, forKey: .interfaceNumber)
      }
    }

    let apiVersion: String?
    let kind: String?
    let family: String
    let interfaceSignatures: [Signature]

    enum CodingKeys: String, CodingKey, CaseIterable {
      case apiVersion, kind
      case family
      case interfaceSignatures
    }

    init(from decoder: any Decoder) throws {
      try decoder.rejectUnknownKeys(CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      apiVersion = try container.decodeIfPresent(String.self, forKey: .apiVersion)
      kind = try container.decodeIfPresent(String.self, forKey: .kind)
      family = try container.decode(String.self, forKey: .family)
      interfaceSignatures = try container.decode([Signature].self, forKey: .interfaceSignatures)
    }
  }

  private static func loadBundledSignatures() throws -> [InterfaceSignature] {
    var signatures: [InterfaceSignature] = []
    for protocolID in PhysicalProtocolID.allCases {
      guard let url = Bundle.module.url(forResource: protocolID.rawValue, withExtension: "json")
      else { continue }
      signatures += try interfaceSignatures(
        decoding: Data(contentsOf: url),
        protocolID: protocolID,
        fileName: url.lastPathComponent
      )
    }
    return signatures
  }

  /// The signatures of one protocol description document, the file `fileName` that the
  /// bundle holds for `protocolID`.
  static func interfaceSignatures(
    decoding data: Data,
    protocolID: PhysicalProtocolID,
    fileName: String
  ) throws -> [InterfaceSignature] {
    let document: ProtocolDescriptionDocument
    do {
      document = try JSONDecoder().decode(ProtocolDescriptionDocument.self, from: data)
    } catch let error as DecodingError {
      throw ControllerRecordProblem("\(fileName): \(error)")
    }
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: document.apiVersion,
      kind: document.kind,
      expected: protocolDescriptionKind
    ) {
      if problem.code != nil { throw problem.located(in: fileName) }
      throw ControllerRecordProblem("\(fileName): \(problem.message)")
    }
    guard document.family == protocolID.rawValue else {
      throw ControllerRecordProblem("\(fileName): family must be \(protocolID.rawValue)")
    }
    return try document.interfaceSignatures.map { signature in
      guard let variant = PhysicalProtocolVariantID(rawValue: signature.variant),
        protocolID.variants.contains(variant)
      else {
        throw ControllerRecordProblem(
          "\(fileName): \(protocolID.rawValue) has no variant \(signature.variant)"
        )
      }
      return InterfaceSignature(
        protocolID: protocolID,
        variant: variant,
        interfaceClass: signature.interfaceClass,
        interfaceSubclass: signature.interfaceSubclass,
        interfaceProtocol: signature.interfaceProtocol,
        requiredInterfaceNumber: signature.interfaceNumber
      )
    }
  }
}
