import Foundation

/// One input change the engine applies, found by diffing a source's snapshot against its baseline.
/// Axes are in the remapping frame: Y points down.
enum RemappingInputChange: Equatable {
  case button(Control, isPressed: Bool)
  case dpad(HatDirection)
  case leftStick(x: Float, y: Float)
  case rightStick(x: Float, y: Float)
  case leftTrigger(Float)
  case rightTrigger(Float)
  case motion(ControllerMotionSample)
  case touch(ControllerTouchSample)
}

extension RemappingEngineState {
  /// Diffs `event` against the last snapshot `source` delivered and applies the changes to
  /// `target`. Each source keeps its own baseline, so two sources feeding one target (a Joy-Con
  /// pair) never release each other's controls.
  mutating func process(
    _ event: ControllerEvent,
    from source: LogicalControllerID,
    into target: LogicalControllerID,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    let baseline = sourceBaselines[source] ?? .neutral
    sourceBaselines[source] = event.state
    let changes =
      Self.changes(from: baseline, to: event.state)
      + event.motion.map(RemappingInputChange.motion)
      + event.touchFrames.map(RemappingInputChange.touch)
    return process(changes: changes, from: target, profile: profile, at: uptimeNanoseconds)
  }

  /// Changes from `old` to `new` in the order the delta pipeline delivered them: buttons in
  /// ``controlOrder``, then the hat, left stick, right stick, left trigger and right trigger.
  static func changes(
    from old: ControllerState,
    to new: ControllerState
  ) -> [RemappingInputChange] {
    var changes: [RemappingInputChange] = []
    for control in controlOrder {
      let isPressed = new.pressed.contains(control)
      guard old.pressed.contains(control) != isPressed else { continue }
      changes.append(.button(control, isPressed: isPressed))
    }
    if old.hat != new.hat { changes.append(.dpad(new.hat)) }
    if old.leftStick != new.leftStick {
      changes.append(.leftStick(x: new.leftStick.x.normalized, y: -new.leftStick.y.normalized))
    }
    if old.rightStick != new.rightStick {
      changes.append(.rightStick(x: new.rightStick.x.normalized, y: -new.rightStick.y.normalized))
    }
    if old.leftTrigger != new.leftTrigger {
      changes.append(.leftTrigger(new.leftTrigger.normalized))
    }
    if old.rightTrigger != new.rightTrigger {
      changes.append(.rightTrigger(new.rightTrigger.normalized))
    }
    return changes
  }

  /// Digital controls in the one order simultaneous changes are delivered in, the same for every
  /// controller.
  static let controlOrder: [Control] =
    [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftStickClick,
      .rightStickClick, .start, .back, .guide, .leftTrigger, .rightTrigger, .capture,
      .touchpadClick, .microphone,
      .leftPaddle2, .rightPaddle2, .leftTrackpadClick, .rightTrackpadClick, .auxiliary3,
      .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary1, .auxiliary2, .leftPaddle1,
      .rightPaddle1,
    ]
}
