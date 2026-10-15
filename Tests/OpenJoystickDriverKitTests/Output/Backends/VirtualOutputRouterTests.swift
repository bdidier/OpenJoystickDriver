import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualOutputRouterTests {
  @Test
  func dispatchesOnlyToCurrentVirtualOutputBackend() async {
    let previous = RecordingVirtualOutputDispatcher()
    let current = RecordingVirtualOutputDispatcher()
    let dispatcher = VirtualOutputRouter()
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)

    dispatcher.setBackend(previous)
    dispatcher.setBackend(current)
    await dispatcher.dispatch(
      ControllerEvent([.press(.south)]),
      labels: .playStation,
      from: identifier
    )
    await dispatcher.activateOutput(for: identifier)

    #expect(previous.states.isEmpty && previous.activations.isEmpty)
    #expect(current.states == [snapshot(.press(.south))])
    #expect(current.labels == [.playStation])
    #expect(current.activations == [identifier])
  }

  @Test
  func explicitSuppressionStopsVirtualOutputDispatch() async {
    let backend = RecordingVirtualOutputDispatcher()
    let dispatcher = VirtualOutputRouter()
    dispatcher.setBackend(backend)
    dispatcher.suppressOutput = true

    await dispatcher.dispatch(
      ControllerEvent([.press(.south)]),
      labels: .standard,
      from: LogicalControllerID(vendorID: 1, productID: 2)
    )
    await dispatcher.activateOutput(for: LogicalControllerID(vendorID: 1, productID: 2))

    #expect(backend.states.isEmpty && backend.activations.isEmpty)
    #expect(backend.suppressOutput)
  }
}

private final class RecordingVirtualOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private let lock = NSLock()
  private var recorded: [(ControllerState, ControllerButtonLabels)] = []
  private var recordedActivations: [LogicalControllerID] = []

  var states: [ControllerState] { lock.withLock { recorded.map(\.0) } }
  var labels: [ControllerButtonLabels] { lock.withLock { recorded.map(\.1) } }
  var activations: [LogicalControllerID] { lock.withLock { recordedActivations } }

  func dispatch(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from _: LogicalControllerID
  ) async {
    await Task.yield()
    lock.withLock { recorded.append((event.state, labels)) }
  }

  func activateOutput(for identifier: LogicalControllerID) {
    lock.withLock { recordedActivations.append(identifier) }
  }
}
