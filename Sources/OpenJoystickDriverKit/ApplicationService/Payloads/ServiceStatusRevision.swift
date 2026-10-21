import Foundation

/// Which service process answered `waitForServiceStatusChange` and how many status changes it has
/// recorded.
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

/// Why the service answered a `waitForServiceStatusChange`.
public enum ServiceStatusEventKind: String, Codable, Equatable, Sendable {
  /// The revision differs from the one the caller sent, or a status change moved it.
  case statusChange
  /// The hold time passed with no change, or the caller's wait ended early; the revision is the
  /// current one.
  case holdElapsed
  /// A client asked every waiting app to show its test notification. The status did not change.
  case testNotification
}

/// The service's reply to `waitForServiceStatusChange`: the current revision and why the service
/// answered now.
public struct ServiceStatusReply: Codable, Equatable, Sendable {
  public let revision: ServiceStatusRevision
  public let event: ServiceStatusEventKind

  public init(revision: ServiceStatusRevision, event: ServiceStatusEventKind) {
    self.revision = revision
    self.event = event
  }
}

/// The service's reply to `sendTestNotification`: how many waiting apps it announced the test
/// notification to. Zero means no app was waiting, so nothing will be shown.
public struct TestNotificationAnnouncement: Codable, Equatable, Sendable {
  public let announcedApps: Int

  public init(announcedApps: Int) { self.announcedApps = announcedApps }
}
