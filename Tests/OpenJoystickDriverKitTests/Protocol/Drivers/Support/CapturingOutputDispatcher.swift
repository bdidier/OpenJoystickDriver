import Foundation

@testable import OpenJoystickDriverKit

final class CapturingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private(set) var events: [ControllerEvent] = []

  func dispatch(
    _ event: ControllerEvent,
    from _: LogicalControllerID
  ) { events.append(event) }

  func activateOutput(for _: LogicalControllerID) {}
}
