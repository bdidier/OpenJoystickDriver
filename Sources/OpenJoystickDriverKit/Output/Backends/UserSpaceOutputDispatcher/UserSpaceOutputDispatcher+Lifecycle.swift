import Foundation

extension UserSpaceOutputDispatcher {
  public typealias OutputCommandHandler =
    @Sendable (LogicalControllerID, ControllerOutputCommand) -> Void

  public enum CreationError: Error, CustomStringConvertible, Sendable {
    case createFailed
    case inputReadDenied
    case inputInjectDenied
    case missingEntitlement(String)

    public var description: String {
      switch self {
      case .createFailed: return "Failed to create virtual HID device"
      case .inputReadDenied: return "Input Monitoring denied for the virtual HID device"
      case .inputInjectDenied: return "Accessibility denied for the virtual HID device"
      case .missingEntitlement(let entitlement): return "Missing entitlement: \(entitlement)"
      }
    }
  }

  internal final class LifecycleState: Sendable {
    private let closed = Locked(false)

    var isOpen: Bool { closed.withLock { !$0 } }

    func close() -> Bool {
      closed.withLock { closed in
        guard !closed else { return false }
        closed = true
        return true
      }
    }
  }

  public var suppressOutput: Bool {
    get { registryLock.withLock { _suppressOutput } }
    set { registryLock.withLock { _suppressOutput = newValue } }
  }

  public var status: VirtualOutputBackendStatus { registryLock.withLock { _status } }
  public func setOutputSuppressed(_ suppressed: Bool) async {
    let suppression: (entries: [Entry], shouldNeutralize: Bool) = registryLock.withLock {
      let changed = !_suppressOutput && suppressed
      _suppressOutput = suppressed
      return (Array(entries.values), changed)
    }
    for entry in suppression.entries {
      _ = try? await entry.sender.submit {
        suppression.shouldNeutralize && !entry.inputReportState.isRemapped
          ? [entry.inputReportState.reset()] + entry.inputReportState.claimChangedAuxiliaryReports()
          : []
      }.value()
    }
  }
  public func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    let senders = registryLock.withLock {
      remappingOutputSuppressed = suppressed
      return entries.values.map(\.sender)
    }
    for sender in senders { _ = try? await sender.submit { [] }.value() }
  }

  public var lastRumbleStatus: String? { registryLock.withLock { _lastRumbleStatus } }

  public func close() async { await beginClose().value }

  /// Creates and neutrally activates one virtual device for each supplied controller.
  public func activate(for identifiers: [LogicalControllerID]) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    var seen = Set<LogicalControllerID>()
    let identifiers = identifiers.filter { seen.insert($0).inserted }
    do {

      for identifier in identifiers {
        let entry = try await entry(for: identifier)
        guard lifecycle.isOpen else { throw CancellationError() }
        try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }
          .value()

      }
      withRegistry { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  public func activate(controller identifier: LogicalControllerID) async throws {
    guard lifecycle.isOpen else { throw CancellationError() }
    do {
      let entry = try await entry(for: identifier)
      guard lifecycle.isOpen else { throw CancellationError() }
      try await entry.sender.submit { [entry] in [entry.inputReportState.currentReport()] }.value()
      withRegistry { recomputeStatusLocked() }
    } catch {
      await close()
      throw error
    }
  }

  @discardableResult
  func beginClose() -> Task<Void, Never> {
    withRegistry {
      if let shutdownTask { return shutdownTask }
      _ = lifecycle.close()
      let resources = Array(entries.values)
      let identifiers = Set(entries.keys).union(creationTasks.keys)
      let tasks = Array(creationTasks.values)
      entries.removeAll()
      for identifier in identifiers { lifecycleGenerations[identifier, default: 0] &+= 1 }
      creationTasks.removeAll()
      creationRetryPolicies.removeAll()
      _status = .off
      tasks.forEach { $0.cancel() }
      let drains = resources.map { $0.beginClose() }
      let shutdown = Task {
        for drain in drains { await drain.value }
        for task in tasks { if let entry = try? await task.value { await entry.close() } }
      }
      shutdownTask = shutdown
      return shutdown
    }
  }

  public func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async {
    try? await deliver(input: event.state, from: identifier, remappedState: nil)
  }

  public func activateOutput(for identifier: LogicalControllerID) async {
    try? await deliver(input: nil, from: identifier, remappedState: nil)
  }

  public func activateOutputReportingFailure(for identifier: LogicalControllerID) async throws {
    try await deliver(input: nil, from: identifier, remappedState: nil)
  }

  @preconcurrency
  public func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    try await deliver(
      input: event.state,
      from: identifier,
      remappedState: nil,
      onPublished: onPublished
    )
  }

  public func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws
  {
    if state == .neutral, !lifecycle.isOpen {
      await close()
      return
    }
    try await deliver(input: nil, from: identifier, remappedState: state)
  }

  internal func isOutputSuppressed(remapped: Bool) -> Bool {
    registryLock.withLock { remapped ? remappingOutputSuppressed : _suppressOutput }
  }
}
