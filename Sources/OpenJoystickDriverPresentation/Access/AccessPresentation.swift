import Foundation
import OpenJoystickDriverKit

/// Words for the values of the access payloads.
enum AccessPresentation {
  static func scopes(_ scopes: [EndpointScope]) -> String {
    scopes.map(scope).joined(separator: ", ")
  }

  static func scope(_ scope: EndpointScope) -> String {
    switch scope {
    case .read: OJDLocalized.string("access.scope.read")
    case .control: OJDLocalized.string("access.scope.control")
    }
  }

  /// How a client was signed, with the publisher's ID for a signed one.
  static func signer(_ kind: CodeSigningIdentity.Kind, _ publisherID: String?) -> String {
    switch kind {
    case .signed:
      publisherID.map { OJDLocalized.formatted("access.signer.signed", $0) }
        ?? OJDLocalized.string("access.signer.signedUnknownPublisher")
    case .platform: OJDLocalized.string("access.signer.platform")
    case .adHoc: OJDLocalized.string("access.signer.adHoc")
    }
  }

  static func transport(_ transport: AccessTransport) -> String {
    switch transport {
    case .socket: OJDLocalized.string("access.transport.socket")
    case .web: OJDLocalized.string("access.transport.web")
    }
  }

  /// The state of the WebSocket in a sentence.
  static func web(_ web: AccessWebStatus) -> String {
    guard web.enabled else { return OJDLocalized.string("access.web.off") }
    guard let port = web.port, let url = web.url, let pagesURL = web.pagesURL else {
      return OJDLocalized.string("access.web.noPort")
    }
    guard web.listening else { return OJDLocalized.formatted("access.web.closed", String(port)) }
    return OJDLocalized.formatted("access.web.on", url, pagesURL)
  }
}
