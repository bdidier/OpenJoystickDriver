import Foundation

/// Driver for every family whose input is a fixed report layout: it decodes raw input reports by
/// the byte offsets and bit masks a ``ControllerInputLayout`` names (a `HIDReportLayout`
/// record's, or the family description's) and drives rumble only through the rumble template. It
/// sends nothing at startup.
public final class ReportLayoutDriver: PhysicalProtocolDriver {
  /// Where a raw-USB rumble template sends its packets.
  public struct USBOutput: Equatable, Sendable {
    public let endpoint: UInt8
    public let timeoutMilliseconds: Int

    public init(endpoint: UInt8, timeoutMilliseconds: Int) {
      self.endpoint = endpoint
      self.timeoutMilliseconds = timeoutMilliseconds
    }
  }

  private let layout: ControllerInputLayout
  private let rumbleTemplate: RumbleOutputTemplate?
  private let usbOutput: USBOutput?
  /// Per hat source, whether its 8-way field has been nonzero in this session.
  private var hatSourceIsLive: [Bool]
  private var state = ControllerState.neutral
  private var lastRumble = RumbleIntensities.off

  /// Creates a driver for one input layout and optional rumble template. A raw-USB template
  /// needs `usbOutput`; a HID template ignores it.
  public init(
    layout: ControllerInputLayout,
    rumbleTemplate: RumbleOutputTemplate? = nil,
    usbOutput: USBOutput? = nil
  ) {
    self.layout = layout
    self.rumbleTemplate = rumbleTemplate
    self.usbOutput = usbOutput
    hatSourceIsLive = Array(repeating: false, count: layout.hat.count)
  }

  /// A new transport session starts from neutral input with no live hat.
  public func resetProtocolState() {
    state = .neutral
    lastRumble = .off
    hatSourceIsLive = Array(repeating: false, count: layout.hat.count)
  }

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan().withRumbleResend(of: rumbleTemplate)
  }

  /// The last rumble again while a motor runs, when the template names a resend interval.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard let rumbleTemplate, let intensities = rumbleTemplate.resendIntensities(after: lastRumble)
    else { return [] }
    return [rumbleWrite(rumbleTemplate, intensities)]
  }

  private func rumbleWrite(
    _ template: RumbleOutputTemplate,
    _ intensities: RumbleIntensities
  ) -> PhysicalOutputWrite {
    guard case .usb = template.target else { return template.write(intensities) }
    guard let usbOutput else {
      preconditionFailure("a raw-USB rumble template needs the driver's USB output")
    }
    return .usb(
      PhysicalUSBOutputPacket(
        endpoint: usbOutput.endpoint,
        bytes: template.reportBytes(intensities),
        timeoutMilliseconds: UInt32(usbOutput.timeoutMilliseconds)
      )
    )
  }
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    rumbleTemplate?.outputCapabilities ?? .none
  }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: layout.controls)
  }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard let rumbleTemplate else { throw .unsupportedCapability(command.capability) }
    let intensities: RumbleIntensities
    switch command {
    case .setRumble(let requested, _): intensities = requested
    case .stopRumble: intensities = .off
    default: throw .unsupportedCapability(command.capability)
    }
    lastRumble = intensities
    return PhysicalOutputPlan(writes: [rumbleWrite(rumbleTemplate, intensities)])
  }

  /// Decodes one input report into the full controller state; a report shorter than the layout
  /// (or longer, when the layout requires an exact length) or with another report ID is ignored.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard bytes.count >= layout.minimumLength,
      !layout.requiresExactLength || bytes.count == layout.minimumLength,
      layout.reportID == nil || bytes[0] == layout.reportID
    else { return nil }
    var next = state
    for button in layout.buttons {
      next.set(button.control, pressed: button.fields.contains { $0.isSet(in: bytes) })
    }
    var sticks: [Float] = [0, 0, 0, 0]
    for axis in layout.axes {
      guard let index = Control.stickAxes.firstIndex(of: axis.control) else {
        continue
      }
      sticks[index] = axis.value(in: bytes)
    }
    next.leftStick = StickPosition(x: sticks[0], y: sticks[1])
    next.rightStick = StickPosition(x: sticks[2], y: sticks[3])
    if !layout.hat.isEmpty { next.hat = hat(bytes) }
    if let trigger = layout.leftTrigger { next.leftTrigger = trigger.value(in: bytes) }
    if let trigger = layout.rightTrigger { next.rightTrigger = trigger.value(in: bytes) }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// The first source's direction that is not neutral. Every 8-way source is read, so each
  /// one's live flag tracks the whole session.
  private func hat(_ bytes: [UInt8]) -> HatDirection {
    var result = HatDirection.neutral
    for (index, source) in layout.hat.enumerated() {
      let direction: HatDirection
      switch source {
      case .eightWay(let field, let neutralUntilNonzero):
        let value = field.value(in: bytes)
        if value != 0 { hatSourceIsLive[index] = true }
        let directions = HatDirection.clockwiseFromNorth
        direction =
          (!neutralUntilNonzero || hatSourceIsLive[index]) && value < directions.count
          ? directions[value] : .neutral
      case .directions(let up, let right, let down, let left):
        direction = HatDirection(
          up: up.isSet(in: bytes),
          right: right.isSet(in: bytes),
          down: down.isSet(in: bytes),
          left: left.isSet(in: bytes)
        )
      case .table(let field, let directions):
        direction = directions[field.value(in: bytes)] ?? .neutral
      }
      if result == .neutral { result = direction }
    }
    return result
  }
}

extension ReportLayoutDriver {
  /// Creates the driver of a family whose description holds the input layout. The rumble
  /// template is the record's when it sets one, otherwise the description's for `variant`; a
  /// raw-USB template sends to `outEndpoint` within the family's `usbTransferTimeoutMs`.
  public convenience init(
    describedBy family: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    rumbleTemplate record: RumbleOutputTemplate?,
    outEndpoint: UInt8,
    tuning: ControllerTuning?
  ) {
    guard let layout = family.protocolDescription.inputLayout else {
      preconditionFailure("\(family.descriptionFileStem).json sets no input layout")
    }
    let template = family.rumbleTemplate(variant: variant, record: record)
    var usbOutput: USBOutput?
    if case .usb? = template?.target {
      usbOutput = USBOutput(
        endpoint: outEndpoint,
        timeoutMilliseconds: family.described(\.usbTransferTimeoutMilliseconds, in: tuning)
      )
    }
    self.init(layout: layout, rumbleTemplate: template, usbOutput: usbOutput)
  }
}
