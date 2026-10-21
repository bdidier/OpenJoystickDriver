import Foundation
import OpenJoystickDriverKit

/// Which lists of the Access form exist. A list with nothing in it is left out; Grant and Create
/// in the toolbar add the first item.
struct AccessLayout: Equatable {
  let showsGrants: Bool
  let showsTokens: Bool
  let showsRefused: Bool
  let showsConnections: Bool

  init(_ status: AccessStatusPayload) {
    showsGrants = !status.grants.isEmpty
    showsTokens = !status.tokens.isEmpty
    showsRefused = !status.refused.isEmpty || !status.refusedTokens.isEmpty
    showsConnections = !status.connections.isEmpty
  }
}
