import Foundation

/// The service's reply to `waitForServiceStatusChange`: which service process answered and how
/// many status changes it has recorded.
///
/// A status change is any change to what `getStatus` or the remapping snapshot reports:
/// controller attach, detach and session state, permissions, the virtual device backend, input
/// connection and recovery, and profile state. A caller compares whole revisions, so a restarted
/// service, whose count starts at 0 again, differs from the one the caller last saw.
public struct ServiceStatusRevision: Codable, Equatable, Sendable {
  /// Seconds the service holds a wait with no change before it replies with the same revision.
  public static let holdSeconds: TimeInterval = 20

  /// Identifies the service process; fixed for its lifetime.
  public let instance: UUID
  /// Status changes recorded since that process started.
  public let generation: UInt64

  public init(instance: UUID, generation: UInt64) {
    self.instance = instance
    self.generation = generation
  }
}

/// Arguments of `waitForServiceStatusChange`: the revision the caller last saw, or nil to read
/// the current one at once.
public struct LocalServiceRPCStatusChangeArguments: Codable, Sendable {
  public let after: ServiceStatusRevision?

  public init(after: ServiceStatusRevision?) { self.after = after }
}
