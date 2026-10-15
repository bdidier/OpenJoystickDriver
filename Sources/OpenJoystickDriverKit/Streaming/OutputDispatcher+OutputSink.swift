import Foundation

/// The virtual-device path: every ``OutputDispatcher`` is an ``OutputSink`` for controller frames,
/// and for gamepad frames when it is also a ``RemappingGamepadSink``.
extension OutputDispatcher {
  public var destination: OutputDestination { .virtualDevice }

  public func consume(
    _ frame: StreamFrame,
    onDelivered: @escaping @Sendable () -> Void
  ) async throws {
    switch frame {
    case .controller(let event, let labels, let identifier):
      try await dispatchPublishing(
        event,
        labels: labels,
        from: identifier,
        onPublished: onDelivered
      )
    case .gamepad(let state, let identifier):
      guard let sink = self as? any RemappingGamepadSink else {
        throw StreamBoundaryError.unsupported(destination)
      }
      try await sink.send(state, for: identifier)
      onDelivered()
    case .observed:
      throw StreamBoundaryError.unsupported(destination)
    }
  }
}
