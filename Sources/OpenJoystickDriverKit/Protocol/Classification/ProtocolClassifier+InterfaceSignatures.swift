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
  /// in family order, as ``ProtocolDescription`` decodes them. The Xbox triples are pinned against
  /// Linux `xpad.c` at the `ControllerSources.lock.json` commit: the `'X','B',0` table entry,
  /// `XPAD_XBOX360_VENDOR` (subclass 93, protocols 1 and 129), `XPAD_XBOXONE_VENDOR` (subclass 71,
  /// protocol 208), the GIP data interface number, and the interrupt IN+OUT endpoint requirement
  /// in `xpad_probe`.
  static let signatures: [InterfaceSignature] = PhysicalProtocolID.allCases.flatMap {
    ProtocolDescription.bundled[$0]?.interfaceSignatures ?? []
  }
}
