import Foundation

/// The signing identifier and signer of a piece of code.
public struct CodeSigningIdentity: Codable, Equatable, Hashable, Sendable {
  /// Who signed the code.
  public enum Kind: String, Codable, Sendable {
    /// Signed with a developer certificate of the publisher `publisherID`.
    case signed = "Signed"
    /// Signed by the platform vendor, such as a system tool.
    case platform = "Platform"
    /// Ad-hoc signed or not signed; any local process can claim this identity.
    case adHoc = "AdHoc"
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

  private static func quoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
