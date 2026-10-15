import Foundation

/// The text form shared by session tokens and port keys: a two-character prefix such as `E-`,
/// then 16 base64url characters that encode 12 bytes.
enum PrefixedIdentifierText {
  /// The number of bytes encoded after the prefix.
  static let byteCount = 12

  /// `prefix` followed by the first 12 bytes of `bytes` as unpadded base64url.
  static func make(prefix: String, bytes: some Sequence<UInt8>) -> String {
    // 12 bytes are 16 base64url characters, short enough to type.
    let encoded = Data(bytes.prefix(byteCount)).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return prefix + encoded
  }

  /// Whether `text` is `prefix` followed by exactly 16 base64url characters.
  static func isWellFormed(_ text: String, prefix: String) -> Bool {
    let body = text.utf8.dropFirst(prefix.utf8.count)
    return text.hasPrefix(prefix) && body.count == 16
      && body.allSatisfy {
        (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
          || $0 == 0x2D || $0 == 0x5F
      }
  }
}
