import Foundation

/// Routes normalized controller input exclusively to the active virtual HID device.
public final class VirtualOutputRouter: OutputDispatcher, RemappingGamepadSink,
  RemappingGamepadOutputControlling, @unchecked Sendable
{
  private let lock = NSLock()
  private var backend: (any OutputDispatcher)?
  private var _suppressOutput = false
  private var remappingOutputSuppressed = false

  public var suppressOutput: Bool {
    get { lock.withLock { _suppressOutput } }
    set {
      lock.withLock {
        _suppressOutput = newValue
        backend?.suppressOutput = newValue
      }
    }
  }

  public init() {}

  public func setBackend(_ newBackend: (any OutputDispatcher)?) {
    lock.withLock {
      backend = newBackend
      backend?.suppressOutput = _suppressOutput
    }
  }

  public func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    let target = lock.withLock {
      remappingOutputSuppressed = suppressed
      return backend
    }
    if let controlling = target as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(suppressed)
    }
  }

  public func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
  {
    let target = lock.withLock { remappingOutputSuppressed && state != .neutral ? nil : backend }
    guard let sink = target as? any RemappingGamepadSink else {
      throw RemappingEventEngineError.sinkUnavailable
    }
    if let controlling = target as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(lock.withLock { remappingOutputSuppressed })
    }
    try await sink.send(state, for: identifier)
  }

  public func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.dispatch(event, from: identifier)
  }

  @preconcurrency
  public func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    try await target?.dispatchPublishing(
      event,
      from: identifier,
      onPublished: onPublished
    )
  }

  public func activateOutput(for identifier: LogicalControllerID) async {
    let target = lock.withLock { _suppressOutput ? nil : backend }
    await target?.activateOutput(for: identifier)
  }
}

extension VirtualOutputRouter: ControllerInputOwnershipListener {
  public func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async {
    let target = lock.withLock { backend }
    await (target as? any ControllerInputOwnershipListener)?.controllerInputOwnershipChanged(
      ownership,
      for: identifier
    )
  }
}

extension VirtualOutputRouter: ControllerLifecycleListener {
  public func controllerDidStop(_ identifier: LogicalControllerID) async {
    let target = lock.withLock { backend }
    if let listener = target as? any ControllerLifecycleListener {
      await listener.controllerDidStop(identifier)
    }
  }
}
