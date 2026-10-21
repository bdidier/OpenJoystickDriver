import Combine
import Foundation
import OpenJoystickDriverKit

/// A program that a grant names: its signature and where it was read.
struct AccessClientCandidate: Equatable, Identifiable {
  let identity: CodeSigningIdentity
  let path: String

  var id: String { identity.accessID }
}

/// The input of the token form.
struct AccessTokenDraft: Equatable {
  var name = ""
  /// One web origin per line; empty for a token that only local programs use.
  var originsText = ""
  var scopes: Set<EndpointScope> = [.read]

  var origins: [String] {
    originsText.split(whereSeparator: \.isNewline).map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
  }
}

/// An operation that waits for the person's confirmation in a window-modal sheet.
enum AccessPending: Identifiable, Equatable {
  case enableEndpoint
  case enableWeb(port: Int?)
  case grantClient(AccessClientCandidate)
  case grantToken(name: String, origins: [String])
  /// `scope` nil removes the whole grant; otherwise only that scope.
  case revokeGrant(id: String, name: String, scope: EndpointScope?)
  case revokeToken(id: String, name: String, scope: EndpointScope?)

  var id: String {
    switch self {
    case .enableEndpoint: "enableEndpoint"
    case .enableWeb: "enableWeb"
    case .grantClient(let candidate): "grantClient.\(candidate.id)"
    case .grantToken(let name, _): "grantToken.\(name)"
    case .revokeGrant(let id, _, let scope): "revokeGrant.\(id).\(scope?.rawValue ?? "all")"
    case .revokeToken(let id, _, let scope): "revokeToken.\(id).\(scope?.rawValue ?? "all")"
    }
  }
}

/// The text and button of a confirmation sheet; its wording matches the action.
struct AccessConfirmation: Equatable {
  let title: String
  /// Warnings first, then the question.
  let lines: [String]
  let confirmTitle: String
  let isDestructive: Bool
}

/// The token a grant created. The service does not keep it, so the sheet that shows it is the
/// only place it can be read.
struct AccessIssuedToken: Identifiable, Equatable {
  let name: String
  let token: String

  var id: String { name }
}

enum AccessSheet: Identifiable, Equatable {
  case confirm(AccessPending)
  case tokenForm
  case issuedToken(AccessIssuedToken)

  var id: String {
    switch self {
    case .confirm(let pending): "confirm.\(pending.id)"
    case .tokenForm: "tokenForm"
    case .issuedToken(let token): "issuedToken.\(token.id)"
    }
  }
}

@MainActor
final class AccessViewModel: ObservableObject {
  enum Load: Equatable {
    case loading
    case loaded(AccessStatusPayload)
    case failed(AccessFailure)
  }

  @Published
  private(set) var load = Load.loading
  @Published
  private(set) var busy = false
  /// Why the latest operation failed.
  @Published
  private(set) var failure: AccessFailure?
  @Published
  var sheet: AccessSheet?
  /// The scopes of the grant that the open confirmation sheet asks for.
  @Published
  var grantScopes: Set<EndpointScope> = [.read]
  @Published
  var tokenDraft = AccessTokenDraft()
  /// The port field of the WebSocket form. It shows the saved port until the person edits it;
  /// empty keeps the saved port.
  @Published
  var portText = "" {
    didSet {
      guard !isFillingPort else { return }
      portEdited = true
      choosesAutomaticPort = false
    }
  }
  /// Whether enabling asks the system for a free port, whatever port is saved.
  @Published
  private(set) var choosesAutomaticPort = false

  private var portEdited = false
  private var isFillingPort = false
  private let service: any AccessService
  private let identityAtPath: (URL) -> CodeSigningIdentity?

  init(
    service: any AccessService = ApplicationServiceAccessService(),
    identityAtPath: @escaping (URL) -> CodeSigningIdentity? = { CodeSigningIdentity.of(path: $0) }
  ) {
    self.service = service
    self.identityAtPath = identityAtPath
  }

  var status: AccessStatusPayload? {
    if case .loaded(let status) = load { return status }
    return nil
  }

  /// The text the empty port field shows: the saved port that an empty field keeps, or
  /// "Automatic" when no port is saved or the person chose automatic.
  var portPlaceholder: String {
    if !choosesAutomaticPort, let port = status?.web.port { return String(port) }
    return OJDLocalized.string("access.web.port.automatic")
  }

  /// Whether a port is saved that the person can replace with an automatic one.
  var canChooseAutomaticPort: Bool { status?.web.port != nil && !choosesAutomaticPort }

  /// Empties the field and makes enabling pick a free port instead of the saved one.
  func chooseAutomaticPort() {
    isFillingPort = true
    portText = ""
    isFillingPort = false
    portEdited = true
    choosesAutomaticPort = true
  }

  /// The port the field names: nil keeps the saved port, 0 asks for a free one. A failure names
  /// a port outside the range a user may bind.
  func webPort() throws -> Int? {
    if choosesAutomaticPort { return 0 }
    let text = portText.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    guard let port = Int(text), AccessWebPorts.allowed.contains(port) else {
      throw AccessFailure(
        message: OJDLocalized.formatted(
          "access.web.portRange",
          AccessWebPorts.allowed.lowerBound,
          AccessWebPorts.allowed.upperBound
        ),
        code: .webPortUnavailable
      )
    }
    return port
  }

  func dismissFailure() { failure = nil }

  func refresh() async {
    do { show(try await service.status()) } catch {
      load = .failed(AccessFailure(error))
    }
  }

  // MARK: Requests that need no confirmation

  func disableEndpoint() async { await apply { try await service.setEnabled(false) } }

  func disableWeb() async { await apply { try await service.setWeb(enabled: false, port: nil) } }

  // MARK: Requests that ask first

  func requestEnableEndpoint() { sheet = .confirm(.enableEndpoint) }

  func requestEnableWeb() {
    perform {
      sheet = .confirm(.enableWeb(port: try webPort()))
    }
  }

  func requestGrant(_ candidate: AccessClientCandidate) {
    guard candidate.identity.kind != .adHoc else {
      failure = AccessFailure(
        message: OJDLocalized.formatted("access.grant.adHoc", candidate.identity.identifier),
        code: .unsignedClient
      )
      return
    }
    grantScopes = [.read]
    sheet = .confirm(.grantClient(candidate))
  }

  /// Asks to grant the program at `url`.
  func requestGrant(programAt url: URL) {
    let url = url.standardizedFileURL
    guard let identity = identityAtPath(url) else {
      failure = AccessFailure(
        message: OJDLocalized.formatted("access.grant.unsigned", url.path),
        code: .unsignedClient
      )
      return
    }
    requestGrant(AccessClientCandidate(identity: identity, path: url.path))
  }

  /// Asks to grant a refused client. A client whose executable the service could not read has no
  /// path to record, so the grant is refused.
  func requestRefusedGrant(_ client: AccessRefusedClient) {
    guard let path = client.path else {
      failure = AccessFailure(
        message: OJDLocalized.formatted("access.grant.noPath", client.identifier),
        code: .unsignedClient
      )
      return
    }
    requestGrant(AccessClientCandidate(identity: client.identity, path: path))
  }

  func requestTokenForm() {
    tokenDraft = AccessTokenDraft()
    sheet = .tokenForm
  }

  /// Moves from the token form to its confirmation.
  func requestGrantToken() {
    let draft = tokenDraft
    guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty, !draft.scopes.isEmpty else {
      failure = AccessFailure(
        message: OJDLocalized.string("access.token.incomplete"),
        code: .invalidTokenName
      )
      return
    }
    guard draft.origins.isEmpty || !draft.scopes.contains(.control) else {
      failure = AccessFailure(
        message: OJDLocalized.string("access.token.originControl"),
        code: .controlScopeWithOrigins
      )
      return
    }
    sheet = .confirm(.grantToken(name: draft.name, origins: draft.origins))
  }

  /// The scopes of a grant that can be revoked one at a time. A grant with a single scope has
  /// none: revoking it removes the whole grant.
  static func scopeChoices(of scopes: [EndpointScope]) -> [EndpointScope] {
    scopes.count > 1 ? scopes : []
  }

  /// Asks to revoke `scope` of the grant, or the whole grant when `scope` is nil.
  func requestRevoke(_ grant: AccessGrantSummary, scope: EndpointScope? = nil) {
    sheet = .confirm(.revokeGrant(id: grant.id, name: grant.identifier, scope: scope))
  }

  /// Asks to revoke `scope` of the token, or the whole token when `scope` is nil.
  func requestRevoke(_ token: AccessTokenSummary, scope: EndpointScope? = nil) {
    sheet = .confirm(.revokeToken(id: token.id, name: token.name, scope: scope))
  }

  func cancelSheet() { sheet = nil }

  func closeIssuedToken() { sheet = nil }

  func confirm(_ pending: AccessPending) async {
    sheet = nil
    switch pending {
    case .enableEndpoint: await apply { try await service.setEnabled(true) }
    case .enableWeb(let port):
      await apply { try await service.setWeb(enabled: true, port: port) }
      if failure == nil, let status {
        portEdited = false
        choosesAutomaticPort = false
        show(status)
      }
    case .grantClient(let candidate):
      let scopes = grantScopes.sorted()
      await apply {
        _ = try await service.grant(candidate.identity, path: candidate.path, scopes: scopes)
        return try await service.status()
      }
    case .grantToken(let name, let origins):
      let scopes = tokenDraft.scopes.sorted()
      await apply {
        let result = try await service.grantToken(name: name, origins: origins, scopes: scopes)
        sheet = .issuedToken(AccessIssuedToken(name: result.grant.name, token: result.token))
        return try await service.status()
      }
    case .revokeGrant(let id, _, let scope), .revokeToken(let id, _, let scope):
      await apply {
        _ = try await service.revoke(id: id, scopes: scope.map { [$0] })
        return try await service.status()
      }
    }
  }

  // MARK: Confirmation text

  func confirmation(for pending: AccessPending) -> AccessConfirmation {
    switch pending {
    case .enableEndpoint:
      return AccessConfirmation(
        title: OJDLocalized.string("access.enable.title"),
        lines: [OJDLocalized.string("access.enable.message")],
        confirmTitle: OJDLocalized.string("access.enable"),
        isDestructive: false
      )
    case .enableWeb(let port):
      return AccessConfirmation(
        title: OJDLocalized.string("access.web.enable.title"),
        lines: [
          OJDLocalized.string("access.web.enable.message"),
          port.map {
            $0 == 0
              ? OJDLocalized.string("access.web.enable.automatic")
              : OJDLocalized.formatted("access.web.enable.port", $0)
          } ?? OJDLocalized.string("access.web.enable.savedPort"),
        ],
        confirmTitle: OJDLocalized.string("access.enable"),
        isDestructive: false
      )
    case .grantClient(let candidate):
      var lines: [String] = []
      if grantScopes.contains(.control) {
        lines.append(OJDLocalized.string("access.grant.controlWarning"))
      }
      if candidate.identity.kind == .platform {
        lines.append(OJDLocalized.string("access.grant.platformWarning"))
      }
      lines.append(
        OJDLocalized.formatted(
          "access.grant.question",
          candidate.identity.identifier,
          AccessPresentation.signer(candidate.identity.kind, candidate.identity.publisherID),
          AccessPresentation.scopes(grantScopes.sorted())
        )
      )
      return AccessConfirmation(
        title: OJDLocalized.formatted("access.grant.title", candidate.identity.identifier),
        lines: lines,
        confirmTitle: OJDLocalized.string("access.grant"),
        isDestructive: false
      )
    case .grantToken(let name, let origins):
      var lines: [String] = []
      if tokenDraft.scopes.contains(.control) {
        lines.append(OJDLocalized.string("access.grant.controlWarning"))
      }
      let scopes = AccessPresentation.scopes(tokenDraft.scopes.sorted())
      lines.append(
        origins.isEmpty
          ? OJDLocalized.formatted("access.token.question", name, scopes)
          : OJDLocalized.formatted(
            "access.token.webQuestion",
            name,
            scopes,
            origins.joined(separator: ", ")
          )
      )
      return AccessConfirmation(
        title: OJDLocalized.formatted("access.token.title", name),
        lines: lines,
        confirmTitle: OJDLocalized.string("access.grant"),
        isDestructive: false
      )
    case .revokeGrant(_, let name, let scope?):
      return partialRevoke(title: "access.revoke.title", name: name, scope: scope)
    case .revokeToken(_, let name, let scope?):
      return partialRevoke(title: "access.revokeToken.title", name: name, scope: scope)
    case .revokeGrant(_, let name, nil):
      return AccessConfirmation(
        title: OJDLocalized.formatted("access.revoke.title", name),
        lines: [OJDLocalized.string("access.revoke.message")],
        confirmTitle: OJDLocalized.string("access.revoke"),
        isDestructive: true
      )
    case .revokeToken(_, let name, nil):
      return AccessConfirmation(
        title: OJDLocalized.formatted("access.revokeToken.title", name),
        lines: [OJDLocalized.string("access.revokeToken.message")],
        confirmTitle: OJDLocalized.string("access.revoke"),
        isDestructive: true
      )
    }
  }

  private func partialRevoke(
    title: String,
    name: String,
    scope: EndpointScope
  )
    -> AccessConfirmation
  {
    AccessConfirmation(
      title: OJDLocalized.formatted(title, name),
      lines: [
        OJDLocalized.formatted("access.revokeScope.message", AccessPresentation.scope(scope))
      ],
      confirmTitle: OJDLocalized.string("access.revoke"),
      isDestructive: true
    )
  }

  // MARK: Private

  private func perform(_ body: () throws -> Void) {
    failure = nil
    do { try body() } catch { failure = AccessFailure(error) }
  }

  /// Runs a request that returns the endpoint's state afterward.
  private func apply(_ request: () async throws -> AccessStatusPayload) async {
    failure = nil
    busy = true
    defer { busy = false }
    do { show(try await request()) } catch { failure = AccessFailure(error) }
  }

  /// Loads `status` and, until the person edits the port field, fills it with the saved port.
  private func show(_ status: AccessStatusPayload) {
    load = .loaded(status)
    guard !portEdited else { return }
    isFillingPort = true
    portText = status.web.port.map(String.init) ?? ""
    isFillingPort = false
  }
}
