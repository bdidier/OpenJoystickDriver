import Foundation

extension UserSpaceOutputDispatcher {
  struct StickTransfer: Equatable, Sendable {
    let deadzone: Float
    let rescalesDeadzone: Bool
  }

  static func stickTransfer(for identifier: LogicalControllerID) -> StickTransfer {
    let catalog = DeviceCatalog.current.withLock { $0 }
    if let deadzone = catalog.record(for: identifier.model)?.tuning.stickDeadzone {
      return StickTransfer(deadzone: deadzone, rescalesDeadzone: true)
    }
    return StickTransfer(deadzone: 0, rescalesDeadzone: false)
  }

  /// How many frames may wait behind a send for `identifier`'s virtual device: the effective
  /// `frameQueueCapacity` of its record, else the `defaults.tuning` of its family's protocol
  /// description, else ``UserSpaceReportSender/fallbackQueueCapacity``.
  static func frameQueueCapacity(for identifier: LogicalControllerID) -> Int {
    let catalog = DeviceCatalog.current.withLock { $0 }
    guard let record = catalog.record(for: identifier.model) else {
      return UserSpaceReportSender.fallbackQueueCapacity
    }
    if let capacity = record.tuning.frameQueueCapacity { return capacity }
    return ProtocolDescription.bundled[record.physicalProtocolID]?.tuning?.frameQueueCapacity
      ?? UserSpaceReportSender.fallbackQueueCapacity
  }

  // MARK: - State mapping (called inside reportLock.withLock)

  /// Replaces every input field of `state` with `input`. This is the one canonical-state
  /// mapping; the dispatcher and the `VirtualHIDProfile` encoders share it.
  static func apply(
    _ input: ControllerState,
    stickTransfer: StickTransfer,
    rightPadIsRightStick: Bool = false,
    to state: inout VirtualGamepadState
  ) {
    let hat = hatValue(for: input.hat)
    state.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
    for control in input.pressed {
      let carried = virtualControl(control, rightPadIsRightStick: rightPadIsRightStick)
      if let bit = Self.buttonBit(for: carried) { state.buttons |= 1 << bit }
    }
    state.hat = hat
    state.leftTriggerPressed = input.pressed.contains(.leftTrigger)
    state.rightTriggerPressed = input.pressed.contains(.rightTrigger)
    // The report's Y points down; the canonical state's Y points up.
    state.leftStickX = Self.axisValue(input.leftStick.x, transfer: stickTransfer)
    state.leftStickY = Self.axisValue(
      BipolarValue(-input.leftStick.y.rawValue),
      transfer: stickTransfer
    )
    state.rightStickX = Self.axisValue(input.rightStick.x, transfer: stickTransfer)
    state.rightStickY = Self.axisValue(
      BipolarValue(-input.rightStick.y.rawValue),
      transfer: stickTransfer
    )
    state.leftTrigger = Self.triggerValue(input.leftTrigger)
    state.rightTrigger = Self.triggerValue(input.rightTrigger)
  }

  /// Replaces every input field of `state` with a remapped gamepad state; remapped sticks pass
  /// through without a dead zone. A digital trigger flag follows its click or, by the
  /// normalization rule, its remapped axis, with `state`'s flag as the previous.
  func apply(_ remapped: RemappingGamepadState, to state: inout VirtualGamepadState) {
    let hat = Self.hatValue(for: remapped.dpadDirection)
    state.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
    for button in remapped.buttons {
      if let bit = Self.buttonBit(for: button) { state.buttons |= 1 << bit }
    }
    state.hat = hat
    state.leftTriggerPressed = Self.remappedTriggerPressed(
      remapped.value(for: .leftTrigger),
      click: remapped.buttons.contains(.leftTrigger),
      wasPressed: state.leftTriggerPressed
    )
    state.rightTriggerPressed = Self.remappedTriggerPressed(
      remapped.value(for: .rightTrigger),
      click: remapped.buttons.contains(.rightTrigger),
      wasPressed: state.rightTriggerPressed
    )
    state.leftStickX = Self.remappedAxisValue(remapped.value(for: .leftStickX))
    state.leftStickY = Self.remappedAxisValue(remapped.value(for: .leftStickY))
    state.rightStickX = Self.remappedAxisValue(remapped.value(for: .rightStickX))
    state.rightStickY = Self.remappedAxisValue(remapped.value(for: .rightStickY))
    state.leftTrigger = Self.remappedTriggerValue(remapped.value(for: .leftTrigger))
    state.rightTrigger = Self.remappedTriggerValue(remapped.value(for: .rightTrigger))
  }

  // MARK: - Button mapping (XInput semantic order)

  /// Whether the controller's right pad is its right stick, read from its resolved record: the
  /// controls it has (the family's, corrected by the record's `capabilityDelta`) include a right
  /// pad click and no right stick click. The classic Steam Controller's record
  /// (`remove: ["RightStickClick"]`) is that, so its pad click is R3. A Steam Deck or Triton has
  /// both controls, so its pad click stays its own control, which no virtual persona carries. A
  /// record or patch that adds or removes either control changes the answer.
  static func rightPadIsRightStick(_ identifier: LogicalControllerID) -> Bool {
    let catalog = DeviceCatalog.current.withLock { $0 }
    return rightPadIsRightStick(record: catalog.record(for: identifier.model))
  }

  /// ``rightPadIsRightStick(_:)`` for an already resolved record; false without one.
  static func rightPadIsRightStick(record: DeviceRuntimeProfile?) -> Bool {
    guard let record, let family = record.physicalProtocolID.protocolDescription.controls?.controls
    else { return false }
    let delta = record.capabilityDelta
    let controls = family.subtracting(delta.absentControls).union(delta.presentControls)
    return controls.contains(.rightTrackpadClick) && !controls.contains(.rightStickClick)
  }

  /// The control a virtual persona carries for `control`. This is the one rule the report mapping
  /// and the remapping passthrough share.
  static func virtualControl(_ control: Control, rightPadIsRightStick: Bool) -> Control {
    control == .rightTrackpadClick && rightPadIsRightStick ? .rightStickClick : control
  }

  /// The one control-to-bit table. A control is the same bit whatever the physical label: PS4
  /// Share, PS Create and Xbox View are `back` (bit 9); PS Options, Xbox Menu and Switch Plus are
  /// `start` (bit 8); Xbox Share and Switch Capture are `capture` (bit 15).
  ///
  /// Carried by neither persona, so `nil`, for these reasons:
  /// - `touchpadClick`, `microphone`, paddles, `auxiliary1...8`, stick and trackpad touch,
  ///   `leftTrackpadClick`: no free button. The generic descriptor's 16 buttons are all used and
  ///   it is a published contract for 1209:4A4F, so another button needs a new PID. The
  ///   sdl-compatible Xbox One report has no slot SDL names for them.
  /// - `rightTrackpadClick`: a pad click is R3 only where the right pad is the right stick
  ///   (``virtualControl(_:rightPadIsRightStick:)``); elsewhere it has no slot.
  /// - `capture` is bit 15 in the generic persona only. The sdl-compatible report is the 16-byte
  ///   Xbox One layout (``XboxGeckoHIDReportFormat``), which has no Share field and clears that
  ///   bit.
  static func buttonBit(for control: Control) -> UInt32? {
    switch control {
    case .south: return 0
    case .east: return 1
    case .west: return 2
    case .north: return 3
    case .leftShoulder: return 4
    case .rightShoulder: return 5
    case .leftStickClick: return 6
    case .rightStickClick: return 7
    case .start: return 8
    case .back: return 9
    case .guide: return 10
    case .capture: return 15
    case .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .rightStickX,
      .rightStickY, .leftTrigger, .rightTrigger, .rightTrackpadClick, .touchpadClick, .microphone,
      .leftPaddle1,
      .leftPaddle2, .rightPaddle1, .rightPaddle2, .auxiliary1, .auxiliary2, .auxiliary3,
      .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch,
      .rightStickTouch, .leftTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch:
      return nil
    }
  }

  // MARK: - Axis + hat helpers

  static func axisValue(_ value: BipolarValue, transfer: StickTransfer) -> Int16 {
    let normalized = value.normalized
    let magnitude = abs(normalized)
    guard magnitude > transfer.deadzone else { return 0 }
    guard transfer.rescalesDeadzone else { return value.rawValue }
    let rescaled = (magnitude - transfer.deadzone) / (1 - transfer.deadzone)
    return Int16(copysignf(rescaled, normalized) * 32_767)
  }

  /// The report's 15-bit trigger, scaled down with truncation. Every 8-bit source (`u = v * 257`)
  /// reaches exactly the value the float path gave it.
  static func triggerValue(_ value: UnipolarValue) -> Int16 {
    Int16(UInt32(value.rawValue) * UInt32(Int16.max) / UInt32(UInt16.max))
  }

  static func remappedAxisValue(_ value: Double) -> Int16 {
    let clamped = Float(value).clamped(to: -1...1)
    guard clamped != 0 else { return 0 }
    return Int16(clamped * 32_767)
  }

  static func remappedTriggerPressed(_ value: Double, click: Bool, wasPressed: Bool) -> Bool {
    click
      || TriggerButtonDerivation.isPressed(
        UnipolarValue(normalized: Float(value)),
        wasPressed: wasPressed
      )
  }

  static func remappedTriggerValue(_ value: Double) -> Int16 {
    Int16(Float(value).clamped(to: 0...1) * 32_767)
  }

  static func hatValue(for direction: HatDirection) -> GamepadHIDDescriptor.Hat {
    switch direction {
    case .neutral: return .neutral
    case .north: return .north
    case .northEast: return .northEast
    case .east: return .east
    case .southEast: return .southEast
    case .south: return .south
    case .southWest: return .southWest
    case .west: return .west
    case .northWest: return .northWest
    }
  }
}
