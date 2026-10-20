import Foundation

public enum RemappingDpadDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case up = "DpadUp"
  case down = "DpadDown"
  case left = "DpadLeft"
  case right = "DpadRight"
}

/// A stick axis or a trigger of the control vocabulary; the raw value is its control id.
public enum RemappingAxis: String, Codable, CaseIterable, Hashable, Sendable {
  case leftStickX = "LeftStickX"
  case leftStickY = "LeftStickY"
  case rightStickX = "RightStickX"
  case rightStickY = "RightStickY"
  case leftTrigger = "LeftTrigger"
  case rightTrigger = "RightTrigger"

  /// The control this axis is.
  public var control: Control {
    switch self {
    case .leftStickX: .leftStickX
    case .leftStickY: .leftStickY
    case .rightStickX: .rightStickX
    case .rightStickY: .rightStickY
    case .leftTrigger: .leftTrigger
    case .rightTrigger: .rightTrigger
    }
  }
}

public enum RemappingAxisDirection: String, Codable, Hashable, Sendable {
  case negative = "Negative"
  case positive = "Positive"
}

/// The controller-side origin of a binding.
public enum RemappingSource: Codable, Equatable, Hashable, Sendable {
  case button(Control)
  case dpad(RemappingDpadDirection)
  case axis(RemappingAxis)
  case axisDirection(RemappingAxis, RemappingAxisDirection)
  case triggerStage(RemappingTriggerSource, RemappingTriggerStage)
  case motionLean(RemappingMotionLeanDirection)
  case touchContact(RemappingTouchSurface)
  case touchGrid(RemappingTouchGridSource)
  case touchSwipe(RemappingTouchSwipeSource)

  private enum Kind: String, Codable {
    case button = "Button"
    case dpad = "Dpad"
    case axis = "Axis"
    case axisDirection = "AxisDirection"
    case triggerStage = "TriggerStage"
    case motionLean = "MotionLean"
    case touchContact = "TouchContact"
    case touchGrid = "TouchGrid"
    case touchSwipe = "TouchSwipe"

    var fields: [CodingKeys] {
      switch self {
      case .button: [.type, .button]
      case .dpad, .motionLean: [.type, .direction]
      case .axis: [.type, .axis]
      case .axisDirection: [.type, .axis, .direction]
      case .triggerStage: [.type, .trigger, .stage]
      case .touchContact: [.type, .surface]
      case .touchGrid: [.type, .surface, .columns, .rows, .column, .row]
      case .touchSwipe: [.type, .surface, .direction, .minimumDistance]
      }
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case button
    case direction
    case axis
    case surface
    case columns
    case rows
    case column
    case row
    case minimumDistance
    case trigger
    case stage
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    try container.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .button: self = .button(try container.decode(Control.self, forKey: .button))
    case .dpad: self = .dpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .axis: self = .axis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .axisDirection:
      self = .axisDirection(
        try container.decode(RemappingAxis.self, forKey: .axis),
        try container.decode(RemappingAxisDirection.self, forKey: .direction)
      )
    case .triggerStage:
      self = .triggerStage(
        try container.decode(RemappingTriggerSource.self, forKey: .trigger),
        try container.decode(RemappingTriggerStage.self, forKey: .stage)
      )
    case .motionLean:
      self = .motionLean(
        try container.decode(RemappingMotionLeanDirection.self, forKey: .direction)
      )
    case .touchContact:
      self = .touchContact(try container.decode(RemappingTouchSurface.self, forKey: .surface))
    case .touchGrid:
      self = .touchGrid(
        RemappingTouchGridSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          columns: try container.decode(Int.self, forKey: .columns),
          rows: try container.decode(Int.self, forKey: .rows),
          column: try container.decode(Int.self, forKey: .column),
          row: try container.decode(Int.self, forKey: .row)
        )
      )
    case .touchSwipe:
      self = .touchSwipe(
        RemappingTouchSwipeSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          direction: try container.decode(RemappingTouchSwipeDirection.self, forKey: .direction),
          minimumDistance: try container.decode(Double.self, forKey: .minimumDistance)
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .button(let button):
      try container.encode(Kind.button, forKey: .type)
      try container.encode(button, forKey: .button)
    case .dpad(let direction):
      try container.encode(Kind.dpad, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .axis(let axis):
      try container.encode(Kind.axis, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .axisDirection(let axis, let direction):
      try container.encode(Kind.axisDirection, forKey: .type)
      try container.encode(axis, forKey: .axis)
      try container.encode(direction, forKey: .direction)
    case .triggerStage(let trigger, let stage):
      try container.encode(Kind.triggerStage, forKey: .type)
      try container.encode(trigger, forKey: .trigger)
      try container.encode(stage, forKey: .stage)
    case .motionLean(let direction):
      try container.encode(Kind.motionLean, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .touchContact(let surface):
      try container.encode(Kind.touchContact, forKey: .type)
      try container.encode(surface, forKey: .surface)
    case .touchGrid(let source):
      try container.encode(Kind.touchGrid, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.columns, forKey: .columns)
      try container.encode(source.rows, forKey: .rows)
      try container.encode(source.column, forKey: .column)
      try container.encode(source.row, forKey: .row)
    case .touchSwipe(let source):
      try container.encode(Kind.touchSwipe, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.direction, forKey: .direction)
      try container.encode(source.minimumDistance, forKey: .minimumDistance)
    }
  }
}

/// A symbolic keyboard key; the raw value is its W3C `KeyboardEvent.code`. Platform adapters
/// translate this value to an OS key code.
public enum RemappingKeyboardKey: String, Codable, CaseIterable, Hashable, Sendable {
  case a = "KeyA"
  case b = "KeyB"
  case c = "KeyC"
  case d = "KeyD"
  case e = "KeyE"
  case f = "KeyF"
  case g = "KeyG"
  case h = "KeyH"
  case i = "KeyI"
  case j = "KeyJ"
  case k = "KeyK"
  case l = "KeyL"
  case m = "KeyM"
  case n = "KeyN"
  case o = "KeyO"
  case p = "KeyP"
  case q = "KeyQ"
  case r = "KeyR"
  case s = "KeyS"
  case t = "KeyT"
  case u = "KeyU"
  case v = "KeyV"
  case w = "KeyW"
  case x = "KeyX"
  case y = "KeyY"
  case z = "KeyZ"
  case digit0 = "Digit0"
  case digit1 = "Digit1"
  case digit2 = "Digit2"
  case digit3 = "Digit3"
  case digit4 = "Digit4"
  case digit5 = "Digit5"
  case digit6 = "Digit6"
  case digit7 = "Digit7"
  case digit8 = "Digit8"
  case digit9 = "Digit9"
  case escape = "Escape"
  case tab = "Tab"
  case capsLock = "CapsLock"
  case space = "Space"
  case returnKey = "Enter"
  case deleteBackward = "Backspace"
  case deleteForward = "Delete"
  case help = "Help"
  case insert = "Insert"
  case home = "Home"
  case end = "End"
  case pageUp = "PageUp"
  case pageDown = "PageDown"
  case arrowUp = "ArrowUp"
  case arrowDown = "ArrowDown"
  case arrowLeft = "ArrowLeft"
  case arrowRight = "ArrowRight"
  case minus = "Minus"
  case equal = "Equal"
  case leftBracket = "BracketLeft"
  case rightBracket = "BracketRight"
  case backslash = "Backslash"
  case semicolon = "Semicolon"
  case quote = "Quote"
  case comma = "Comma"
  case period = "Period"
  case slash = "Slash"
  case grave = "Backquote"
  case section = "IntlBackslash"
  case f1 = "F1"
  case f2 = "F2"
  case f3 = "F3"
  case f4 = "F4"
  case f5 = "F5"
  case f6 = "F6"
  case f7 = "F7"
  case f8 = "F8"
  case f9 = "F9"
  case f10 = "F10"
  case f11 = "F11"
  case f12 = "F12"
  case f13 = "F13"
  case f14 = "F14"
  case f15 = "F15"
  case f16 = "F16"
  case f17 = "F17"
  case f18 = "F18"
  case f19 = "F19"
  case f20 = "F20"
  case keypad0 = "Numpad0"
  case keypad1 = "Numpad1"
  case keypad2 = "Numpad2"
  case keypad3 = "Numpad3"
  case keypad4 = "Numpad4"
  case keypad5 = "Numpad5"
  case keypad6 = "Numpad6"
  case keypad7 = "Numpad7"
  case keypad8 = "Numpad8"
  case keypad9 = "Numpad9"
  case keypadDecimal = "NumpadDecimal"
  case keypadMultiply = "NumpadMultiply"
  case keypadPlus = "NumpadAdd"
  case keypadClear = "NumLock"
  case keypadDivide = "NumpadDivide"
  case keypadEnter = "NumpadEnter"
  case keypadMinus = "NumpadSubtract"
  case keypadEqual = "NumpadEqual"
}

public enum RemappingKeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
  case meta = "Meta"
  case control = "Control"
  case alt = "Alt"
  case shift = "Shift"
}

public enum RemappingMouseButton: String, Codable, CaseIterable, Hashable, Sendable {
  case left = "Left"
  case right = "Right"
  case middle = "Middle"
  case back = "Back"
  case forward = "Forward"
}

public enum RemappingPointerAxis: String, Codable, CaseIterable, Hashable, Sendable {
  case x = "X"
  case y = "Y"
}
