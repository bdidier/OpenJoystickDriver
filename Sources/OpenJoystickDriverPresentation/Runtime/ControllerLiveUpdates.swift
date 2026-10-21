import Foundation
import OpenJoystickDriverKit

/// Waits on the service for status changes.
protocol ControllerChangeSource: Sendable {
  /// Returns the service's status revision once it differs from `revision`, or after the
  /// service's hold time with the same one. A nil `revision` returns the current one at once.
  func waitForChange(after revision: ServiceStatusRevision?) async throws -> ServiceStatusRevision
}

/// How the app learns of service status changes.
enum ControllerLiveUpdateMode: Equatable {
  /// No wait has answered yet.
  case starting
  /// A wait is open on the service, which answers it when the status changes.
  case subscribed
  /// The wait is unavailable for `reason`; the app reads the service every
  /// `ControllerLiveUpdates.fallbackPollSeconds` and tries the wait again on each read.
  case polling(reason: String)
}

/// Keeps the Controllers list, detail, Access, status item and menu current from service
/// notifications.
///
/// One wait is open on the service at a time. Each answer triggers `refresh`: a changed revision
/// or service instance is a change, a first answer is the baseline, and an answer after the
/// service's hold time covers the status no event announces, such as input health that turns
/// stale with time. When the wait fails, the mode becomes `.polling`, `modeChanged` reports it,
/// the reason is logged once, and `refresh` runs every `fallbackPollSeconds` until a wait
/// succeeds again.
@MainActor
final class ControllerLiveUpdates {
  static let fallbackPollSeconds: Double = 1

  private(set) var mode = ControllerLiveUpdateMode.starting {
    didSet { if oldValue != mode { modeChanged(mode) } }
  }
  private let source: any ControllerChangeSource
  private let refresh: @MainActor () async -> Void
  private let log: @MainActor (String) -> Void
  private let modeChanged: @MainActor (ControllerLiveUpdateMode) -> Void
  private let fallbackPollSeconds: Double
  private var task: Task<Void, Never>?

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
        if case .polling = mode {
          log("[ControllerLiveUpdates] Service subscription restored; polling stopped.")
        }
        mode = .subscribed
        revision = next
        await refresh()
      } catch {
        if Task.isCancelled { return }
        let reason = error.localizedDescription
        if mode != .polling(reason: reason) {
          mode = .polling(reason: reason)
          log(
            "[ControllerLiveUpdates] Service subscription unavailable (\(reason)); "
              + "polling every \(fallbackPollSeconds) s."
          )
        }
        revision = nil
        await refresh()
        try? await Task.sleep(nanoseconds: UInt64(fallbackPollSeconds * 1_000_000_000))
      }
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
