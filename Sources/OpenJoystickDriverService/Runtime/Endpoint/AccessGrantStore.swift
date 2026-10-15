import Foundation
import OpenJoystickDriverKit

enum AccessGrantStoreError: Error, Equatable, LocalizedError, Sendable {
  case damaged
  /// The file's `apiVersion` or `kind` is not the supported one; the text says what was found.
  case unsupported(DocumentHeaderProblem)
  case unknownClient(String)
  case notGrantable(CodeSigningIdentity.Kind)
  case noScope
  case serviceStopped
  case duplicateToken(String)
  case invalidTokenName(String)
  case invalidOrigin(String)
  case portUnavailable(Int)
  case originsWithControl

  /// The code, then what it means and how to fix it, in the language of the user, then the value
  /// that the error is about.
  private static func coded(_ code: ErrorCode, detail: String? = nil) -> String {
    "\(code.rawValue): \(code.localizedExplanation)" + (detail.map { " (\($0))" } ?? "")
  }

  /// The code of the error, whose localized text `errorDescription` leads with.
  var code: ErrorCode {
    switch self {
    case .damaged: .damagedAccessGrants
    case .unsupported: .unsupportedAccessGrants
    case .unknownClient: .unknownAccessClient
    case .notGrantable: .ungrantableClient
    case .noScope: .noAccessScope
    case .serviceStopped: .serviceStopping
    case .duplicateToken: .duplicateTokenName
    case .invalidTokenName: .invalidTokenName
    case .invalidOrigin: .invalidWebOrigin
    case .portUnavailable: .webPortUnavailable
    case .originsWithControl: .controlScopeWithOrigins
    }
  }

  var errorDescription: String? {
    switch self {
    case .damaged, .noScope, .serviceStopped, .originsWithControl:
      Self.coded(code)
    case .unsupported(let problem):
      Self.coded(code, detail: problem.description)
    case .unknownClient(let id): Self.coded(code, detail: id)
    case .notGrantable(let kind): Self.coded(code, detail: kind.rawValue)
    case .duplicateToken(let name), .invalidTokenName(let name): Self.coded(code, detail: name)
    case .invalidOrigin(let origin): Self.coded(code, detail: origin)
    case .portUnavailable(let port): Self.coded(code, detail: String(port))
    }
  }
}

/// The contents of `AccessGrants.json`: whether the endpoint and its WebSocket are on, and the
/// granted clients and tokens.
struct AccessGrantFile: Equatable, Sendable {
  /// The `kind` of the file.
  static let kind = "AccessGrants"

  var enabled = false
  var grants: [AccessGrant] = []
  var tokens: [AccessTokenGrant] = []
  var web = AccessWebSettings()

  func grant(for identity: CodeSigningIdentity) -> AccessGrant? {
    grants.first { $0.identity == identity }
  }

  /// Adds `scopes` to the client's grant, or grants it; returns the grant as stored.
  @discardableResult
  mutating func grant(
    _ identity: CodeSigningIdentity,
    scopes: [EndpointScope],
    path: String,
    at date: Date
  ) -> AccessGrant {
    let previous = grant(for: identity)?.scopes ?? []
    let grant = AccessGrant(
      identity: identity,
      scopes: previous + scopes,
      grantedAt: ISO8601DateFormatter().string(from: date),
      path: path
    )
    if let index = grants.firstIndex(where: { $0.identity == identity }) {
      grants[index] = grant
    } else {
      grants.append(grant)
    }
    return grant
  }

  /// Removes `scopes`, or every scope when nil; returns the grant left, or nil when none is.
  mutating func revoke(id: String, scopes: [EndpointScope]?) throws -> AccessGrant? {
    guard let index = grants.firstIndex(where: { $0.identity.accessID == id }) else {
      throw AccessGrantStoreError.unknownClient(id)
    }
    let grant = grants[index]
    let remaining = scopes.map { revoked in grant.scopes.filter { !revoked.contains($0) } } ?? []
    guard !remaining.isEmpty else {
      grants.remove(at: index)
      return nil
    }
    grants[index] = AccessGrant(
      identity: grant.identity,
      scopes: remaining,
      grantedAt: grant.grantedAt,
      path: grant.path
    )
    return grants[index]
  }

  /// Whether every `control` scope carries `controlGrantedAt`, which the service writes with it.
  ///
  /// Builds before the scope worked stored it without effect, so honoring it now would turn on
  /// input to a virtual gamepad that the user never saw work. A file with such a scope is damaged
  /// instead, and the user grants again.
  var controlScopesAreMarked: Bool {
    grants.allSatisfy { !$0.scopes.contains(.control) || $0.controlGrantedAt != nil }
      && tokens.allSatisfy { !$0.scopes.contains(.control) || $0.controlGrantedAt != nil }
  }

  /// Removes `control` from tokens that have origins, and tokens left with no scope; returns the
  /// names of the removed tokens.
  ///
  /// Earlier builds allowed the combination; a page never drives a pad, so the stored scope has no
  /// use, and dropping it keeps the rest of the file valid.
  mutating func dropControlFromTokensWithOrigins() -> [String] {
    var removed: [String] = []
    tokens = tokens.compactMap { grant in
      guard grant.scopes.contains(.control), !grant.origins.isEmpty else { return grant }
      let scopes = grant.scopes.filter { $0 != .control }
      guard !scopes.isEmpty else {
        removed.append(grant.name)
        return nil
      }
      return AccessTokenGrant(
        name: grant.name,
        tokenSHA256: grant.tokenSHA256,
        origins: grant.origins,
        scopes: scopes,
        grantedAt: grant.grantedAt
      )
    }
    return removed
  }
}

/// Why a file's `apiVersion` or `kind` is not the supported one.
struct AccessGrantHeaderProblem: Error, Equatable, Sendable { let problem: DocumentHeaderProblem }

extension AccessGrantFile: Codable {
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case apiVersion, kind, enabled, grants, tokens, web
  }

  init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      throw AccessGrantHeaderProblem(problem: problem)
    }
    enabled = try container.decode(Bool.self, forKey: .enabled)
    grants = try container.decode([AccessGrant].self, forKey: .grants)
    tokens = try container.decode([AccessTokenGrant].self, forKey: .tokens)
    web = try container.decode(AccessWebSettings.self, forKey: .web)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(grants, forKey: .grants)
    try container.encode(tokens, forKey: .tokens)
    try container.encode(web, forKey: .web)
  }
}

/// Reads and writes `AccessGrants.json`; the application service is its only writer.
///
/// A damaged file is an error, not an empty one, so a mistake never silently turns the endpoint
/// off or drops grants that the user would then grant again.
struct AccessGrantStore: Sendable {
  static let fileName = "AccessGrants.json"

  let url: URL

  init(directory: URL = RemappingProfileLibrary.defaultDirectory) {
    url = directory.appendingPathComponent(Self.fileName, isDirectory: false)
  }

  /// The folder whose files the WebSocket's port serves as overlay pages.
  var pagesDirectory: URL {
    url.deletingLastPathComponent().appendingPathComponent("Overlays", isDirectory: true)
  }

  func load() throws -> AccessGrantFile {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return AccessGrantFile()
    }
    let decoded: AccessGrantFile?
    do {
      decoded = try JSONDecoder().decode(AccessGrantFile.self, from: data)
    } catch let problem as AccessGrantHeaderProblem {
      throw AccessGrantStoreError.unsupported(problem.problem)
    } catch {
      decoded = nil
    }
    guard var file = decoded,
      file.grants.allSatisfy({ $0.identity.requirement != nil && !$0.scopes.isEmpty }),
      file.hasValidTokensAndWeb, file.controlScopesAreMarked
    else { throw AccessGrantStoreError.damaged }
    for name in file.dropControlFromTokensWithOrigins() {
      print("[AccessGrantStore] Ignored token \(name): only control scope, with origins")
    }
    return file
  }

  func save(_ file: AccessGrantFile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try RemappingProfileLibrary.createPrivateDirectory(url.deletingLastPathComponent())
    try RemappingProfileLibrary.writePrivate(encoder.encode(file), to: url)
  }
}

/// The clients and tokens the endpoint refused in the last day, newest first, so `ojd access list`
/// can offer them for a grant.
struct AccessRefusalLog: Sendable {
  static let retention: TimeInterval = 86_400

  private var entries: [(client: AccessRefusedClient, date: Date)] = []
  private var tokenEntries: [(token: AccessRefusedToken, date: Date)] = []

  mutating func record(
    _ identity: CodeSigningIdentity,
    path: String?,
    scopes: [EndpointScope],
    at date: Date
  ) {
    let client = AccessRefusedClient(
      identity: identity,
      path: path,
      scopes: scopes,
      reason: ErrorCode.notGranted.rawValue,
      refusalTime: ISO8601DateFormatter().string(from: date)
    )
    entries.removeAll {
      $0.client.id == client.id || date.timeIntervalSince($0.date) > Self.retention
    }
    entries.insert((client, date), at: 0)
  }

  /// Records a `hello` whose token matched no grant, when `name` is nil, or was not granted the
  /// scopes or the origin.
  mutating func recordToken(
    name: String?,
    origin: String?,
    transport: AccessTransport,
    scopes: [EndpointScope],
    at date: Date
  ) {
    let token = AccessRefusedToken(
      name: name,
      origin: origin,
      transport: transport,
      scopes: scopes,
      reason: ErrorCode.notGranted.rawValue,
      refusalTime: ISO8601DateFormatter().string(from: date)
    )
    tokenEntries.removeAll {
      ($0.token.name, $0.token.origin, $0.token.transport) == (name, origin, transport)
        || date.timeIntervalSince($0.date) > Self.retention
    }
    tokenEntries.insert((token, date), at: 0)
  }

  mutating func remove(id: String) { entries.removeAll { $0.client.id == id } }

  func clients(at now: Date) -> [AccessRefusedClient] {
    entries.filter { now.timeIntervalSince($0.date) <= Self.retention }.map(\.client)
  }

  func tokens(at now: Date) -> [AccessRefusedToken] {
    tokenEntries.filter { now.timeIntervalSince($0.date) <= Self.retention }.map(\.token)
  }
}
