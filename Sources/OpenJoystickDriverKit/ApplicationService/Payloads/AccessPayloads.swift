import CryptoKit
import Foundation

/// What an endpoint client may do: `Read` controller events, or `Control` a virtual gamepad.
public enum EndpointScope: String, Codable, CaseIterable, Comparable, Sendable {
  case read = "Read"
  case control = "Control"

  /// The scope on the command line: the lowercase kebab-case form of its name, such as `read`.
  public var commandLineName: String { CommandLineName.kebab(rawValue) }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

extension CodeSigningIdentity {
  /// The short ID that `ojd access` shows for a client: the first 8 hex digits of the SHA-256 of
  /// its publisher kind, publisher ID, and signing identifier.
  public var accessID: String {
    let key = "\(kind.rawValue)\n\(publisherID ?? "")\n\(identifier)"
    return SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
  }
}

/// A client the user allowed to use the endpoint, as stored in `AccessGrants.json`.
public struct AccessGrant: Codable, Equatable, Sendable {
  public let kind: CodeSigningIdentity.Kind
  public let identifier: String
  public let publisherID: String?
  /// Sorted, without repeats.
  public let scopes: [EndpointScope]
  /// ISO 8601 time of the latest `ojd access grant` for this client.
  public let grantedAt: String
  /// Where the client was when it was granted; for display only.
  public let path: String
  /// Set whenever the grant holds `control`, marking it as granted after the scope worked; a file
  /// with a `control` scope but no mark is damaged.
  public let controlGrantedAt: String?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case publisher
    case identifier
    case scopes
    case grantedAt
    case path
    case controlGrantedAt
  }

  private struct StoredPublisher: Codable {
    let kind: CodeSigningIdentity.Kind
    let id: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
      case kind
      case id
    }

    init(kind: CodeSigningIdentity.Kind, id: String?) {
      self.kind = kind
      self.id = id
    }

    init(from decoder: any Decoder) throws {
      try decoder.rejectUnknownKeys(CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      kind = try container.decode(CodeSigningIdentity.Kind.self, forKey: .kind)
      id = try container.decodeIfPresent(String.self, forKey: .id)
    }
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let publisher = try container.decode(StoredPublisher.self, forKey: .publisher)
    kind = publisher.kind
    publisherID = publisher.id
    identifier = try container.decode(String.self, forKey: .identifier)
    scopes = try container.decode([EndpointScope].self, forKey: .scopes)
    grantedAt = try container.decode(String.self, forKey: .grantedAt)
    path = try container.decode(String.self, forKey: .path)
    controlGrantedAt = try container.decodeIfPresent(String.self, forKey: .controlGrantedAt)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(StoredPublisher(kind: kind, id: publisherID), forKey: .publisher)
    try container.encode(identifier, forKey: .identifier)
    try container.encode(scopes, forKey: .scopes)
    try container.encode(grantedAt, forKey: .grantedAt)
    try container.encode(path, forKey: .path)
    try container.encodeIfPresent(controlGrantedAt, forKey: .controlGrantedAt)
  }

  public init(
    identity: CodeSigningIdentity,
    scopes: [EndpointScope],
    grantedAt: String,
    path: String
  ) {
    kind = identity.kind
    identifier = identity.identifier
    publisherID = identity.publisherID
    self.scopes = Array(Set(scopes)).sorted()
    self.grantedAt = grantedAt
    self.path = path
    controlGrantedAt = scopes.contains(.control) ? grantedAt : nil
  }

  public var identity: CodeSigningIdentity {
    CodeSigningIdentity(kind: kind, identifier: identifier, publisherID: publisherID)
  }
}

/// Who published a client: how it was signed, and the publisher's ID when it has one.
public struct AccessPublisher: Codable, Equatable, Sendable {
  public let kind: CodeSigningIdentity.Kind
  public let id: String?

  public init(kind: CodeSigningIdentity.Kind, id: String?) {
    self.kind = kind
    self.id = id
  }
}

/// A grant as `ojd access` prints it, with its client ID.
public struct AccessGrantSummary: Codable, Equatable, Sendable {
  public let id: String
  /// The publisher, a sub-object because every `--json` document has its own `kind`.
  public let publisher: AccessPublisher
  public let identifier: String
  public let scopes: [EndpointScope]
  /// RFC 3339 time of the latest grant.
  public let grantTime: String
  public let path: String

  public init(_ grant: AccessGrant) {
    id = grant.identity.accessID
    publisher = AccessPublisher(kind: grant.kind, id: grant.publisherID)
    identifier = grant.identifier
    scopes = grant.scopes
    grantTime = grant.grantedAt
    path = grant.path
  }
}

/// A client the endpoint refused in the last 24 hours.
public struct AccessRefusedClient: Codable, Equatable, Sendable {
  public let id: String
  public let publisher: AccessPublisher
  public let identifier: String
  /// The client's executable, when the service could read it.
  public let path: String?
  public let scopes: [EndpointScope]
  /// The error code the client got, such as `E1002`.
  public let reason: String
  /// RFC 3339 time of the latest refusal.
  public let refusalTime: String

  public init(
    identity: CodeSigningIdentity,
    path: String?,
    scopes: [EndpointScope],
    reason: String,
    refusalTime: String
  ) {
    id = identity.accessID
    publisher = AccessPublisher(kind: identity.kind, id: identity.publisherID)
    identifier = identity.identifier
    self.path = path
    self.scopes = Array(Set(scopes)).sorted()
    self.reason = reason
    self.refusalTime = refusalTime
  }

  public var identity: CodeSigningIdentity {
    CodeSigningIdentity(
      kind: publisher.kind,
      identifier: identifier,
      publisherID: publisher.id
    )
  }
}

/// How a client reaches the endpoint: the Unix socket, or the WebSocket on `127.0.0.1`.
public enum AccessTransport: String, Codable, Sendable {
  case socket = "Socket"
  case web = "Web"
}

/// A client connected to the endpoint.
public struct AccessConnection: Codable, Equatable, Sendable {
  /// The client ID, or `token:NAME` for a token client.
  public let id: String
  /// The signing identifier, or the token name.
  public let identifier: String
  public let scopes: [EndpointScope]
  public let transport: AccessTransport

  public init(id: String, identifier: String, scopes: [EndpointScope], transport: AccessTransport) {
    self.id = id
    self.identifier = identifier
    self.scopes = scopes
    self.transport = transport
  }

  public init(identity: CodeSigningIdentity, scopes: [EndpointScope]) {
    self.init(
      id: identity.accessID,
      identifier: identity.identifier,
      scopes: scopes,
      transport: .socket
    )
  }
}

/// A token grant as `ojd access` prints it; the token itself is shown only when it is granted.
public struct AccessTokenSummary: Codable, Equatable, Sendable {
  /// `token:NAME`.
  public let id: String
  public let name: String
  /// The web origins, as `scheme://host[:port]`, whose pages may use the token on the WebSocket.
  public let origins: [String]
  public let scopes: [EndpointScope]
  /// RFC 3339 time of the latest grant.
  public let grantTime: String

  public init(name: String, origins: [String], scopes: [EndpointScope], grantTime: String) {
    id = "token:\(name)"
    self.name = name
    self.origins = origins
    self.scopes = scopes
    self.grantTime = grantTime
  }
}

/// A `hello` with a token that the endpoint refused in the last 24 hours.
public struct AccessRefusedToken: Codable, Equatable, Sendable {
  /// The grant the token belongs to; nil for a token that matches no grant.
  public let name: String?
  /// The page's origin; WebSocket only.
  public let origin: String?
  public let transport: AccessTransport
  public let scopes: [EndpointScope]
  public let reason: String
  /// RFC 3339 time of the latest refusal.
  public let refusalTime: String

  public init(
    name: String?,
    origin: String?,
    transport: AccessTransport,
    scopes: [EndpointScope],
    reason: String,
    refusalTime: String
  ) {
    self.name = name
    self.origin = origin
    self.transport = transport
    self.scopes = Array(Set(scopes)).sorted()
    self.reason = reason
    self.refusalTime = refusalTime
  }
}

/// The WebSocket and the overlay pages on `127.0.0.1`.
public struct AccessWebStatus: Codable, Equatable, Sendable {
  public let enabled: Bool
  public let listening: Bool
  /// Nil until the first `ojd access web enable`, which picks a free port unless one is given.
  public let port: Int?
  /// `ws://127.0.0.1:PORT/endpoint`; nil without a port.
  public let url: String?
  /// `http://127.0.0.1:PORT/`, where the overlay pages are served; nil without a port.
  public let pagesURL: String?
  /// The folder the overlay pages are served from.
  public let pagesPath: String

  public init(enabled: Bool, listening: Bool, port: Int?, pagesPath: String) {
    self.enabled = enabled
    self.listening = listening
    self.port = port
    url = port.map { "ws://127.0.0.1:\($0)/endpoint" }
    pagesURL = port.map { "http://127.0.0.1:\($0)/" }
    self.pagesPath = pagesPath
  }
}

/// The endpoint's state, its grants, and the clients it refused recently.
public struct AccessStatusPayload: Codable, Equatable, Sendable {
  public let enabled: Bool
  /// Where the endpoint listens while it is enabled.
  public let socketPath: String
  public let connections: [AccessConnection]
  public let grants: [AccessGrantSummary]
  public let refused: [AccessRefusedClient]
  public let web: AccessWebStatus
  public let tokens: [AccessTokenSummary]
  public let refusedTokens: [AccessRefusedToken]

  public init(
    enabled: Bool,
    socketPath: String,
    connections: [AccessConnection],
    grants: [AccessGrantSummary],
    refused: [AccessRefusedClient],
    web: AccessWebStatus,
    tokens: [AccessTokenSummary],
    refusedTokens: [AccessRefusedToken]
  ) {
    self.enabled = enabled
    self.socketPath = socketPath
    self.connections = connections
    self.grants = grants
    self.refused = refused
    self.web = web
    self.tokens = tokens
    self.refusedTokens = refusedTokens
  }
}

/// The result of `ojd access grant --token`: the token, which is shown only this once.
public struct AccessTokenGrantResult: Codable, Equatable, Sendable {
  public let token: String
  public let grant: AccessTokenSummary

  public init(token: String, grant: AccessTokenSummary) {
    self.token = token
    self.grant = grant
  }
}

package struct AccessEnabledArguments: Codable, Sendable {
  package let enabled: Bool
}

package struct AccessGrantArguments: Codable, Sendable {
  package let identity: CodeSigningIdentity
  package let path: String
  package let scopes: [EndpointScope]
}

package struct AccessTokenGrantArguments: Codable, Sendable {
  package let name: String
  package let origins: [String]
  package let scopes: [EndpointScope]
}

package struct AccessWebArguments: Codable, Sendable {
  package let enabled: Bool
  /// Nil keeps the saved port.
  package let port: Int?
}

package struct AccessRevokeArguments: Codable, Sendable {
  package let id: String
  /// Nil revokes every scope.
  package let scopes: [EndpointScope]?
}

/// The result of `ojd access revoke`.
public struct AccessRevokeResult: Codable, Equatable, Sendable {
  public let id: String
  /// The client grant left after the revoke; nil when no scope is left or `id` is a token.
  public let grant: AccessGrantSummary?
  /// The token grant left after the revoke; nil when no scope is left or `id` is a client.
  public let token: AccessTokenSummary?
  /// Live connections that were closed with `E1005`.
  public let closedConnections: Int

  public init(
    id: String,
    grant: AccessGrantSummary?,
    token: AccessTokenSummary? = nil,
    closedConnections: Int
  ) {
    self.id = id
    self.grant = grant
    self.token = token
    self.closedConnections = closedConnections
  }
}
