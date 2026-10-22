import Foundation
import OpenJoystickDriverKit
import Security

extension CodeSigningIdentity {
  /// The compiled `requirementText`; nil for ad-hoc code or a requirement that does not compile.
  public var requirement: SecRequirement? {
    guard let requirementText else { return nil }
    var requirement: SecRequirement?
    guard
      SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement)
        == errSecSuccess
    else { return nil }
    return requirement
  }

  /// The identity of this process; it does not change while the process runs.
  public static let current: Self? = {
    var code: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
    return of(code)
  }()

  /// The identity of running code.
  public static func of(_ code: SecCode) -> Self? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    return of(staticCode)
  }

  /// The identity of code on disk, such as an app bundle or a tool at a path.
  public static func of(_ staticCode: SecStaticCode) -> Self? {
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String
    else { return nil }
    let publisherID = values[kSecCodeInfoTeamIdentifier as String] as? String
    for kind in [Kind.signed, .platform] {
      let candidate = Self(
        kind: kind,
        identifier: identifier,
        publisherID: publisherID
      )
      if let requirement = candidate.requirement,
        SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement) == errSecSuccess
      {
        return candidate
      }
    }
    return Self(kind: .adHoc, identifier: identifier, publisherID: publisherID)
  }

  /// The identity of the code at `url`; nil when the path holds no signed code.
  public static func of(path url: URL) -> Self? {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }
    return of(staticCode)
  }
}

extension LocalSocketPeer {
  /// The running code of the peer, resolved by its audit token.
  public func code() -> SecCode? {
    let tokenData = withUnsafeBytes(of: auditToken) { Data($0) }
    let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess
    else { return nil }
    return code
  }

  /// True when the peer's code is valid and, if given, satisfies `requirement`.
  public func satisfies(_ requirement: SecRequirement?) -> Bool {
    guard let code = code() else { return false }
    return SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess
  }
}
