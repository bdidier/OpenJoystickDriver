import Foundation

/// A code that no release raises any more. Its number is never reused, so `ojd explain` still
/// answers for it. `Resources/ErrorCodes.json` is the source; a test keeps this list equal to the
/// catalog entries whose status is `retired`.
public struct RetiredErrorCode: Equatable, Sendable {
  public let code: String
  public let domain: ErrorCode.Domain
  /// The release that stopped raising the code.
  public let retiredIn: String

  public static let all: [Self] = [
    Self(code: "E1003", domain: .endpoint, retiredIn: "0.6.0-alpha.1")
  ]

  /// The retired code with this number, in any letter case, or nil.
  public static func named(_ code: String) -> Self? {
    all.first { $0.code == code.uppercased() }
  }
}
