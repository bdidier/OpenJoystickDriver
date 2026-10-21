import Foundation

/// The service's reply to `waitForControllerInventoryChange`: the count of controller attach,
/// detach and state changes since the service started.
public struct ControllerInventoryChangePayload: Codable, Equatable, Sendable {
  /// Seconds the service holds a wait with no change before it replies with the same generation.
  public static let holdSeconds: TimeInterval = 20

  public let generation: UInt64

  public init(generation: UInt64) { self.generation = generation }
}

/// Arguments of `waitForControllerInventoryChange`: the generation the caller last saw, or nil to
/// read the current one at once.
public struct LocalServiceRPCInventoryChangeArguments: Codable, Sendable {
  public let after: UInt64?

  public init(after: UInt64?) { self.after = after }
}
