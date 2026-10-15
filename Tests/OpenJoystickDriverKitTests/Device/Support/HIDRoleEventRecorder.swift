import Foundation

@testable import OpenJoystickDriverKit

/// Records every event batch with the controller that dispatched it.
final class HIDRoleEventRecorder: OutputDispatcher, @unchecked Sendable {
  private let lock = NSLock()
  private var dispatched: [(LogicalControllerID, ControllerState)] = []
  private var suppressed = false

  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  func dispatch(
    _ event: ControllerEvent,
    labels _: ControllerButtonLabels,
    from identifier: LogicalControllerID
  ) { lock.withLock { dispatched.append((identifier, event.state)) } }

  func activateOutput(for _: LogicalControllerID) {}

  /// Controls pressed in any state dispatched from `identifier`.
  func pressed(from identifier: LogicalControllerID) -> Set<Control> {
    lock.withLock {
      dispatched.filter { $0.0 == identifier }.reduce(into: []) { $0.formUnion($1.1.pressed) }
    }
  }
}
