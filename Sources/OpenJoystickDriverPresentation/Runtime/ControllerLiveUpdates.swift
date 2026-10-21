import Foundation
import OpenJoystickDriverKit

/// Waits on the service for controller inventory changes.
protocol ControllerChangeSource: Sendable {
  /// Returns the service's change generation once it differs from `generation`, or after the
  /// service's hold time with the same one. A nil `generation` returns the current one at once.
  func waitForChange(after generation: UInt64?) async throws -> UInt64
}

/// How the app learns of controller changes.
enum ControllerLiveUpdateMode: Equatable {
  /// No wait has answered yet.
  case starting
  /// The service pushes each attach, detach and state change over its socket.
  case subscribed
  /// The subscription is unavailable for `reason`; the app reads the service every
  /// `ControllerLiveUpdates.fallbackPollSeconds` and tries the subscription again on each read.
  case polling(reason: String)
}

/// Keeps the Controllers list, detail, status item and menu current from service notifications.
///
/// One wait is open on the service at a time. A changed generation triggers `refresh`. When the
/// wait fails, the mode becomes `.polling`, the reason is logged once, and `refresh` runs every
/// `fallbackPollSeconds` until a wait succeeds again.
@MainActor
final class ControllerLiveUpdates {
  static let fallbackPollSeconds: Double = 1

  private(set) var mode = ControllerLiveUpdateMode.starting
  private let source: any ControllerChangeSource
  private let refresh: @MainActor () async -> Void
  private let log: @MainActor (String) -> Void
  private let fallbackPollNanoseconds: UInt64
  private var task: Task<Void, Never>?

  init(
    source: any ControllerChangeSource,
    fallbackPollSeconds: Double = ControllerLiveUpdates.fallbackPollSeconds,
    log: @escaping @MainActor (String) -> Void = { print($0) },
    refresh: @escaping @MainActor () async -> Void
  ) {
    self.source = source
    self.refresh = refresh
    self.log = log
    fallbackPollNanoseconds = UInt64(fallbackPollSeconds * 1_000_000_000)
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
    var generation: UInt64?
    var needsCatchUp = false
    while !Task.isCancelled {
      do {
        let next = try await source.waitForChange(after: generation)
        if Task.isCancelled { return }
        if mode != .subscribed {
          if case .polling = mode {
            log("[ControllerLiveUpdates] Service subscription restored; polling stopped.")
            needsCatchUp = true
          }
          mode = .subscribed
        }
        if needsCatchUp || (generation.map { $0 != next } ?? false) {
          needsCatchUp = false
          await refresh()
        }
        generation = next
      } catch {
        if Task.isCancelled { return }
        let reason = error.localizedDescription
        if mode != .polling(reason: reason) {
          mode = .polling(reason: reason)
          log(
            "[ControllerLiveUpdates] Service subscription unavailable (\(reason)); "
              + "polling every \(Int(Self.fallbackPollSeconds)) s."
          )
        }
        generation = nil
        await refresh()
        try? await Task.sleep(nanoseconds: fallbackPollNanoseconds)
      }
    }
  }
}

extension ApplicationServiceClientGateway: ControllerChangeSource {
  func waitForChange(after generation: UInt64?) async throws -> UInt64 {
    await ensureConnection()
    return try await client.waitForControllerInventoryChange(after: generation).generation
  }
}
