import Foundation
import Security

/// The signing identifier and signer of a piece of code.
public struct CodeSigningIdentity: Codable, Equatable, Hashable, Sendable {
  /// Who signed the code.
  public enum Kind: String, Codable, Sendable {
    /// Signed with a developer certificate of the publisher `publisherID`.
    case signed
    /// Signed by the platform vendor, such as a system tool.
    case platform
    /// Ad-hoc signed or not signed; any local process can claim this identity.
    case adHoc = "ad-hoc"

    public init(from decoder: any Decoder) throws {
      let name = try decoder.singleValueContainer().decode(String.self)
      guard let kind = Self(rawValue: name) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "unknown publisher kind '\(name)'."
              + RenamedWord.hints(for: [name], kind: .publisherKind)
          )
        )
      }
      self = kind
    }
  }

  private enum CodingKeys: String, CodingKey {
    case publisher
    case identifier
  }

  private struct Publisher: Codable {
    let kind: Kind
    let id: String?
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let publisher = try container.decode(Publisher.self, forKey: .publisher)
    self.init(
      kind: publisher.kind,
      identifier: try container.decode(String.self, forKey: .identifier),
      publisherID: publisher.id
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Publisher(kind: kind, id: publisherID), forKey: .publisher)
    try container.encode(identifier, forKey: .identifier)
  }

  public let kind: Kind
  public let identifier: String
  /// The publisher's ID: the signing team's identifier for a signed identity.
  public let publisherID: String?

  public init(kind: Kind, identifier: String, publisherID: String?) {
    self.kind = kind
    self.identifier = identifier
    self.publisherID = publisherID
  }

  /// The requirement that code with this identity satisfies; nil for ad-hoc code.
  public var requirementText: String? {
    let identifierClause = "identifier \(Self.quoted(identifier))"
    switch kind {
    case .signed:
      guard let publisherID else { return nil }
      return "\(identifierClause) and anchor apple generic and certificate leaf[subject.OU] = "
        + Self.quoted(publisherID)
    case .platform: return "\(identifierClause) and anchor apple"
    case .adHoc: return nil
    }
  }

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

  private static func quoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
