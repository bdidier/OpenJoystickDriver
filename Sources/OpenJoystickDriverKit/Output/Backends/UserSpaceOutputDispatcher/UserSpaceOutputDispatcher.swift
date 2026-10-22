import Foundation

/// Publishes one virtual gamepad for each connected physical controller.
///
/// The host supplies a ``VirtualHIDDevicePublisher`` that creates the native virtual HID device;
/// this class owns the per-controller report queues, the input state each device carries, and the
/// backend status. This path does not run in the USB DriverKit extension.
public final class UserSpaceOutputDispatcher: VirtualOutputDispatching,
  VirtualOutputControllerActivating, RemappingGamepadSink, RemappingGamepadOutputControlling,
  @unchecked Sendable
{

  internal let format: any VirtualGamepadReportFormat
  internal let onOutputCommand: OutputCommandHandler?
  internal let onControllerDidStop: (@Sendable (LogicalControllerID) async -> Void)?
  internal let lifecycle = LifecycleState()
  internal let backendFactory:
    @Sendable (LogicalControllerID) async throws -> any VirtualDeviceBackend
  internal let registryLock = NSLock()
  internal var entries: [LogicalControllerID: Entry] = [:]
  internal var creationTasks: [LogicalControllerID: Task<Entry, Error>] = [:]
  internal var creationRetryPolicies: [LogicalControllerID: UserSpaceDeviceCreationRetryPolicy] =
    [:]
  internal var lifecycleGenerations: [LogicalControllerID: UInt64] = [:]
  internal var shutdownTask: Task<Void, Never>?
  internal var _suppressOutput = false
  internal var remappingOutputSuppressed = false
  /// Written only under `registryLock`; a change sets `statusChangePending`, and
  /// ``withRegistry(_:)`` announces it after the lock is released.
  internal var _status: VirtualOutputBackendStatus = .off {
    didSet { if oldValue != _status { statusChangePending = true } }
  }
  internal var statusChangePending = false
  internal var _lastRumbleStatus: String?

  /// Publishes each controller's device through `publisher` with the identity `profile` and the
  /// reports `format` describes.
  @preconcurrency
  package init(
    publisher: any VirtualHIDDevicePublisher,
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    onOutputCommand: OutputCommandHandler? = nil,
    onControllerDidStop: (@Sendable (LogicalControllerID) async -> Void)? = nil
  ) {
    self.format = format
    self.onOutputCommand = onOutputCommand
    self.onControllerDidStop = onControllerDidStop
    self.backendFactory = { identifier in
      try publisher.createDevice(for: identifier, profile: profile, format: format)
    }
  }

  init(
    testBackendFactory:
      @escaping @Sendable (LogicalControllerID) async throws -> any VirtualDeviceBackend,
    format: any VirtualGamepadReportFormat = OJDGenericGamepadFormat(),
    onControllerDidStop: (@Sendable (LogicalControllerID) async -> Void)? = nil
  ) {
    self.format = format
    onOutputCommand = nil
    self.onControllerDidStop = onControllerDidStop
    self.backendFactory = testBackendFactory
  }

  deinit { beginClose() }
}

extension UserSpaceOutputDispatcher: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: LogicalControllerID) async {
    let resources = withRegistry { () -> (Entry?, Task<Entry, Error>?) in
      lifecycleGenerations[identifier, default: 0] &+= 1
      let creationTask = creationTasks.removeValue(forKey: identifier)
      creationRetryPolicies.removeValue(forKey: identifier)
      let removed = entries.removeValue(forKey: identifier)
      recomputeStatusLocked()
      return (removed, creationTask)
    }
    await resources.0?.close()
    resources.1?.cancel()
    if let creationTask = resources.1, let entry = try? await creationTask.value {
      await entry.close()
    }
    await onControllerDidStop?(identifier)
  }
}
