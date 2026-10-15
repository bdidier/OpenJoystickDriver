import Foundation
import OpenJoystickDriverKit

final class RemappingPhysicalOutputBridge: RemappingPhysicalOutputSink, Sendable {
  private struct WeakManager { weak var manager: DeviceManager? }

  private let attached = Locked(WeakManager())

  func attach(_ manager: DeviceManager) { attached.withLock { $0.manager = manager } }

  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: LogicalControllerID
  ) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    do {
      try await manager.consume(
        MappingOutputClaim(output, active: active, owner: owner),
        for: identifier
      )
    } catch { throw RemappingEventEngineError.sinkUnavailable }
  }

  func releaseAll(for identifier: LogicalControllerID) async throws {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    do { try await manager.consume(MappingOutputRelease(), for: identifier) } catch {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }

  func setProfileColor(_ color: ControllerColor?, for identifier: LogicalControllerID) async throws
  {
    guard let manager = attached.withLock({ $0.manager }) else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    do { try await manager.consume(ProfileColorClaim(color), for: identifier) } catch {
      throw RemappingEventEngineError.sinkUnavailable
    }
  }
}
