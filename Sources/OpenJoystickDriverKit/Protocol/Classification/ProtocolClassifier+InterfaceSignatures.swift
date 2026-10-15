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

  /// The `$schema` values a protocol description may declare.
  static let protocolDescriptionSchemaIDs: Set<String> = [
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
      + "Resources/Schemas/v1beta1/protocol-description.schema.json"
  ]

  private struct ProtocolDescriptionDocument: Decodable {
    struct Signature: Decodable {
      let variant: String
      let interfaceClass: UInt8
      let interfaceSubclass: UInt8
      let interfaceProtocol: UInt8
      let interfaceNumber: UInt8?
    }

    let schema: String
    let family: String
    let interfaceSignatures: [Signature]

    enum CodingKeys: String, CodingKey {
      case schema = "$schema"
      case family
      case interfaceSignatures
    }
  }

  private static func loadBundledSignatures() throws -> [InterfaceSignature] {
    var signatures: [InterfaceSignature] = []
    for protocolID in PhysicalProtocolID.allCases {
      guard let url = Bundle.module.url(forResource: protocolID.rawValue, withExtension: "json")
      else { continue }
      let document = try JSONDecoder().decode(
        ProtocolDescriptionDocument.self,
        from: Data(contentsOf: url)
      )
      guard protocolDescriptionSchemaIDs.contains(document.schema) else {
        throw ControllerRecordProblem("\(url.lastPathComponent): unknown $schema")
      }
      guard document.family == protocolID.rawValue else {
        throw ControllerRecordProblem(
          "\(url.lastPathComponent): family must be \(protocolID.rawValue)"
        )
      }
      for signature in document.interfaceSignatures {
        guard let variant = PhysicalProtocolVariantID(rawValue: signature.variant) else {
          throw ControllerRecordProblem(
            "\(url.lastPathComponent): unknown variant \(signature.variant)"
          )
        }
        signatures.append(
          InterfaceSignature(
            protocolID: protocolID,
            variant: variant,
            interfaceClass: signature.interfaceClass,
            interfaceSubclass: signature.interfaceSubclass,
            interfaceProtocol: signature.interfaceProtocol,
            requiredInterfaceNumber: signature.interfaceNumber
          )
        )
      }
    }
    return signatures
  }
}
