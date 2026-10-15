import OpenJoystickDriverKit

/// What one automatic dispatch publishes through the backend it leased.
enum AutomaticOutputDelivery: Sendable {
  case input(ControllerEvent, ControllerButtonLabels)
  case activation
  case remapped(RemappingGamepadState)

  func publish(
    through backend: any VirtualOutputDispatching,
    for identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void = {}
  ) async throws {
    switch self {
    case .remapped(let state):
      guard let sink = backend as? any RemappingGamepadSink else {
        throw RemappingEventEngineError.sinkUnavailable
      }
      try await sink.send(state, for: identifier)
    case .input(let event, let labels):
      try await backend.dispatchPublishing(
        event,
        labels: labels,
        from: identifier,
        onPublished: onPublished
      )
    case .activation: try await backend.activateOutputReportingFailure(for: identifier)
    }
  }
}
