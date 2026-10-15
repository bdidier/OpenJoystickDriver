import CryptoKit
import Foundation

/// The stable, user-facing slot of one controller: its model, the USB port it is plugged into,
/// and the interface it is reached through.
///
/// A port key is `U-` and an HMAC of `vid:pid:locationID:interface` under a key that is created
/// once per installation and kept in the service's defaults. It stays the same across reconnects
/// and service restarts while the controller uses the same port, and changes when it moves to
/// another port. It never includes the serial number. A controller with no location ID has no
/// port key.
public struct ControllerPortKey: Hashable, Sendable {
  /// The defaults key that holds the installation's 32-byte key.
  public static let installationKeyDefaultsKey = "ControllerPortKeyInstallationKey"
  /// The prefix of every port key.
  static let prefix = "U-"

  /// Swift initializes a static `let` once, on first use, so concurrent first calls share it.
  private static let installationKey = installationKey(in: .standard)
  // Output routing and profile selection ask for port keys repeatedly, and each is an HMAC.
  private static let cachedKeys = Locked<[LogicalControllerID: Self?]>([:])

  /// The text form: `U-` and 16 base64url characters.
  public let rawValue: String

  /// The port key written as `text`, or nil when `text` is not `U-` and 16 base64url characters.
  public init?(rawValue text: String) {
    guard PrefixedIdentifierText.isWellFormed(text, prefix: Self.prefix) else { return nil }
    rawValue = text
  }

  /// The port key of `controller` under the installation key; nil without a location ID.
  public static func of(_ controller: LogicalControllerID) -> Self? {
    if let cached = cachedKeys.withLock({ $0[controller] }) { return cached }
    let portKey = of(controller, installationKey: installationKey)
    cachedKeys.withLock { $0[controller] = portKey }
    return portKey
  }

  /// The port key of `controller` under `installationKey`; nil without a location ID.
  public static func of(
    _ controller: LogicalControllerID,
    installationKey: SymmetricKey
  ) -> Self? {
    guard let locationID = controller.address?.locationID else { return nil }
    let identity = controller.hardware
    let interface = controller.address?.interfaceNumber.map { String(format: "%02X", $0) } ?? "-"
    let preimage = String(
      format: "%04X:%04X:%08X:%@",
      identity.model.vendorID,
      identity.model.productID,
      locationID,
      interface
    )
    let digest = HMAC<SHA256>.authenticationCode(for: Data(preimage.utf8), using: installationKey)
    return Self(rawValue: PrefixedIdentifierText.make(prefix: prefix, bytes: digest))
  }

  /// The installation key stored in `defaults`, created and stored there when it is absent or
  /// malformed.
  public static func installationKey(in defaults: UserDefaults) -> SymmetricKey {
    if let data = defaults.data(forKey: installationKeyDefaultsKey), data.count == 32 {
      return SymmetricKey(data: data)
    }
    let key = SymmetricKey(size: .bits256)
    defaults.set(key.withUnsafeBytes { Data($0) }, forKey: installationKeyDefaultsKey)
    return key
  }
}

extension ControllerPortKey: Codable {
  /// Decodes the text form; text that is not a port key fails to decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let portKey = ControllerPortKey(rawValue: text) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "A port key is U- and 16 base64url characters."
      )
    }
    self = portKey
  }

  /// Encodes the text form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ControllerPortKey: CustomStringConvertible {
  /// The text form.
  public var description: String { rawValue }
}

extension LogicalControllerID {
  /// The port key of this controller; nil without a location ID. See ``ControllerPortKey``.
  public var portKey: ControllerPortKey? { ControllerPortKey.of(self) }
}
