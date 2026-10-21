import Foundation
import OpenJoystickDriverKit

/// Waits on the service for status changes.
protocol ControllerChangeSource: Sendable {
  /// Returns the service's status revision once it differs from `revision`, or after the
  /// service's hold time with the same one. A nil `revision` returns the current one at once.
  func waitForChange(after revision: ServiceStatusRevision?) async throws -> ServiceStatusRevision
}

/// Why the wait for service status changes failed, as the banner states it.
enum ControllerLiveUpdateFailure: Equatable, Sendable {
  case serviceClosedConnection
  case timeout
  case other

  init(_ error: any Error) {
    switch error {
    case LocalServiceRPCError.serviceClosedConnection: self = .serviceClosedConnection
    case ApplicationServiceClientError.timeout, LocalServiceRPCError.timeout: self = .timeout
    default: self = .other
    }
  }

  /// Localization key of the banner detail.
  var detailKey: String {
    switch self {
    case .serviceClosedConnection: return "banner.liveUpdates.detail.closed"
    case .timeout: return "banner.liveUpdates.detail.timeout"
    case .other: return "banner.liveUpdates.detail.other"
    }
  }
}

/// How the app learns of service status changes.
enum ControllerLiveUpdateMode: Equatable {
  /// No wait has answered yet.
  case starting
  /// A wait is open on the service, which answers it when the status changes.
  case subscribed
  /// The wait is unavailable; the app reads the service every
  /// `ControllerLiveUpdates.fallbackPollSeconds` and tries the wait again on each read. `detail`
  /// is the error's own text, for the log only.
  case polling(failure: ControllerLiveUpdateFailure, detail: String)
}

/// Keeps the Controllers list, detail, Access, status item and menu current from service
/// notifications.
///
/// One wait is open on the service at a time. A first answer is the baseline and a changed
/// revision, including a different service instance, is a change; each refreshes. The service
/// announces every status change, including input reports that are overdue, so a held wait that
/// ends with no change refreshes nothing. When the wait fails, the mode becomes `.polling`, the
/// error is logged once, and `refresh` runs every `fallbackPollSeconds` until a wait succeeds
/// again. `modeChanged` reports polling only after `failuresBeforeReporting` consecutive
/// failures, so a service restart does not flash a banner, and reports the restored wait.
@MainActor
final class ControllerLiveUpdates {
  static let fallbackPollSeconds: Double = 1
  static let failuresBeforeReporting = 3

  private(set) var mode = ControllerLiveUpdateMode.starting
  private let source: any ControllerChangeSource
  private let refresh: @MainActor () async -> Void
  private let log: @MainActor (String) -> Void
  private let modeChanged: @MainActor (ControllerLiveUpdateMode) -> Void
  private let fallbackPollSeconds: Double
  private var task: Task<Void, Never>?
  private var consecutiveFailures = 0
  private var reportedMode: ControllerLiveUpdateMode?

  init(
    source: any ControllerChangeSource,
    fallbackPollSeconds: Double = ControllerLiveUpdates.fallbackPollSeconds,
    log: @escaping @MainActor (String) -> Void = { print($0) },
    modeChanged: @escaping @MainActor (ControllerLiveUpdateMode) -> Void,
    refresh: @escaping @MainActor () async -> Void
  ) {
    self.source = source
    self.refresh = refresh
    self.log = log
    self.modeChanged = modeChanged
    self.fallbackPollSeconds = fallbackPollSeconds
  }

  func start() {
    guard task == nil else { return }
    task = Task { @MainActor [weak self] in await self?.run() }
  }

  func stop() {
    task?.cancel()
    task = nil
  }

  private func run() async {
    var revision: ServiceStatusRevision?
    while !Task.isCancelled {
      do {
        let next = try await source.waitForChange(after: revision)
        if Task.isCancelled { return }
        recordSuccess()
        let changed = next != revision
        revision = next
        if changed { await refresh() }
      } catch {
        if Task.isCancelled { return }
        recordFailure(error)
        revision = nil
        await refresh()
        try? await Task.sleep(nanoseconds: UInt64(fallbackPollSeconds * 1_000_000_000))
      }
    }
  }

  private func recordSuccess() {
    if case .polling = mode {
      log("[ControllerLiveUpdates] Service subscription restored; polling stopped.")
    }
    consecutiveFailures = 0
    mode = .subscribed
    if reportedMode != nil {
      reportedMode = nil
      modeChanged(.subscribed)
    }
  }

  private func recordFailure(_ error: any Error) {
    consecutiveFailures += 1
    let next = ControllerLiveUpdateMode.polling(
      failure: ControllerLiveUpdateFailure(error),
      detail: error.localizedDescription
    )
    if mode != next {
      if case .polling = mode {
      } else {
        log(
          "[ControllerLiveUpdates] Service subscription unavailable "
            + "(\(error.localizedDescription)); polling every \(fallbackPollSeconds) s."
        )
      }
      mode = next
    }
    if consecutiveFailures >= Self.failuresBeforeReporting, reportedMode != next {
      reportedMode = next
      modeChanged(next)
    }
  }
}

extension ApplicationServiceClientGateway: ControllerChangeSource {
  func waitForChange(
    after revision: ServiceStatusRevision?
  ) async throws -> ServiceStatusRevision {
    await ensureConnection()
    return try await client.waitForServiceStatusChange(after: revision)
  }
}
