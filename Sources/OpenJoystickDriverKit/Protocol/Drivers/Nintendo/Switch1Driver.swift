import Foundation

private let switchProFullReportID: UInt8 = 0x30
private let switchProFullReportMinLength = 12
private let switchProStickCenter: UInt16 = 2048
private let switchProStickMax: Float = 2047

public enum NintendoControllerLayout: Sendable {
  case pro
  case leftJoyCon
  case rightJoyCon
}

/// Driver for Nintendo Switch Pro Controller and Joy-Con full input reports.
///
/// Linux `hid-nintendo.c` uses report `0x30`, a packed 24-bit button field,
/// and two packed 12-bit stick fields. This experimental slice uses default
/// center calibration until physical hardware can verify SPI calibration reads.
public final class Switch1Driver: PhysicalProtocolDriver {

  private enum ReportOffset {
    static let reportID = 0
    static let buttons = 3
    static let leftStick = 6
    static let rightStick = 9
  }

  public let layout: NintendoControllerLayout
  /// The bound variant: only a wired Pro Controller takes the USB setup commands, and Bluetooth
  /// startup reports need wider spacing.
  private let isBluetooth: Bool
  private var sensorSamples = NintendoSensorSamples()
  private var motionCalibration = NintendoMotionCalibration.nominal
  private var pendingMotionCalibration: Set<SubcommandRequest.SPIRead.Purpose> = []
  /// The subcommand report, counter rule and startup requests from the family's description.
  private let subcommands: SubcommandPlan
  private var factoryMotionBytes: [UInt8]?
  private var userMotionBytes: [UInt8]?
  private var state = ControllerState.neutral
  private var outputPacketNumber: UInt8 = 0
  private var physicalRumbleData =
    SwitchProRumbleCodec.encode(intensity: 0) + SwitchProRumbleCodec.encode(intensity: 0)

  public init(layout: NintendoControllerLayout = .pro, isBluetooth: Bool = false) {
    self.layout = layout
    self.isBluetooth = isBluetooth
    guard let subcommands = PhysicalProtocolID.nintendoSwitch1.protocolDescription.subcommands
    else { fatalError("[ProtocolDescription] nintendo.switch1 has no subcommands") }
    self.subcommands = subcommands
  }

  /// A new transport session starts from neutral input and re-anchors motion time.
  public func resetProtocolState() {
    state = .neutral
    sensorSamples.reset()
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    let motors: [PhysicalRumbleMotor]
    switch layout {
    case .pro: motors = [.leftMain, .rightMain]
    case .leftJoyCon: motors = [.leftMain]
    case .rightJoyCon: motors = [.rightMain]
    }
    return PhysicalControllerOutputCapabilities(
      rumbleMotors: motors,
      lightingFeatures: [.playerIndicator]
    )
  }

  public var defaultColor: ControllerColor? { nil }

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(hasStartupRecovery: true)
      .withDefaults(of: .nintendoSwitch1, variant: isBluetooth ? .bluetoothClassic : .usb)
  }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    let controls: Set<Control>
    switch layout {
    case .pro:
      controls = Control.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTrigger, .rightTrigger, .guide, .capture,
      ])
    case .leftJoyCon:
      controls = [
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .leftStickClick,
        .leftShoulder, .leftTrigger, .back,
        .capture, .auxiliary3, .auxiliary4,
      ]
    case .rightJoyCon:
      controls = [
        .south, .east, .west, .north, .rightStickX, .rightStickY, .rightStickClick,
        .rightShoulder, .rightTrigger, .start, .guide, .auxiliary5, .auxiliary6,
      ]
    }
    return ControllerCapabilities(
      controls: controls,
      digitalTriggers: controls.intersection([.leftTrigger, .rightTrigger]),
      motion: true
    )
  }

  /// The subcommand reports and calibration requests; the USB handshake commands are the
  /// description's startup writes.
  public func startupWrites() -> [PhysicalOutputWrite] {
    startupReports().map { .hidOutput($0) }
  }

  /// Each Joy-Con drives only its own side. The player subcommand repeats the last rumble.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _): return rumblePlan(intensities)
    case .stopRumble: return rumblePlan(.off)
    case .setPlayerIndicator(let indicator):
      let patterns: [PhysicalPlayerIndicator: UInt8] = [
        .off: 0x00, .player1: 0x01, .player2: 0x03, .player3: 0x07, .player4: 0x0F,
      ]
      return PhysicalOutputPlan(writes: [
        .hidOutput(subcommand(0x30, data: [patterns[indicator] ?? 0]))
      ])
    default: throw .unsupportedCapability(command.capability)
    }
  }

  private func rumblePlan(_ intensities: RumbleIntensities) -> PhysicalOutputPlan {
    let left = layout == .rightJoyCon ? 0 : intensities.leftMain.byte
    let right = layout == .leftJoyCon ? 0 : intensities.rightMain.byte
    physicalRumbleData =
      SwitchProRumbleCodec.encode(intensity: left) + SwitchProRumbleCodec.encode(intensity: right)
    var bytes = [UInt8](repeating: 0, count: 10)
    bytes[0] = 0x10
    bytes[1] = nextPacketNumber()
    bytes.replaceSubrange(2..<10, with: physicalRumbleData)
    return PhysicalOutputPlan(writes: [
      .hidOutput(PhysicalHIDOutputReport(reportID: 0x10, bytes: bytes))
    ])
  }

  /// Decodes one full `0x30` report; a `0x21` subcommand reply only feeds motion calibration.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    if bytes.first == 0x21 {
      consumeMotionCalibrationReply(bytes)
      return nil
    }
    guard bytes.count >= switchProFullReportMinLength,
      bytes[ReportOffset.reportID] == switchProFullReportID
    else { return nil }

    let buttonMask: UInt32
    switch layout {
    case .pro: buttonMask = 0x00FF_FFFF
    case .leftJoyCon: buttonMask = 0x00FF_2900
    case .rightJoyCon: buttonMask = 0x0000_16FF
    }
    let buttons = readUInt24LE(bytes, offset: ReportOffset.buttons) & buttonMask
    let left = readStick(bytes, offset: ReportOffset.leftStick)
    let right = readStick(bytes, offset: ReportOffset.rightStick)

    var next = state
    for (mask, control) in buttonTable { next.set(control, pressed: buttons & mask != 0) }
    next.hat = mapDpad(
      up: buttons & 0x0002_0000 != 0,
      right: buttons & 0x0004_0000 != 0,
      down: buttons & 0x0001_0000 != 0,
      left: buttons & 0x0008_0000 != 0
    )
    if layout != .rightJoyCon {
      next.leftStick = StickPosition(x: normalizeStick(left.x), y: -normalizeStick(left.y))
    }
    if layout != .leftJoyCon {
      next.rightStick = StickPosition(x: normalizeStick(right.x), y: -normalizeStick(right.y))
    }
    let motion = sensorSamples.decode(
      bytes,
      receivedAt: receivedAt.nanoseconds,
      layout: layout,
      calibration: motionCalibration
    )
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next, motion: motion)
  }

  /// Button masks and the Nintendo-label controls they report; SL and SR only on a Joy-Con.
  private var buttonTable: [(UInt32, Control)] {
    switch layout {
    case .pro: Self.proButtonTable
    case .leftJoyCon: Self.leftJoyConButtonTable
    case .rightJoyCon: Self.rightJoyConButtonTable
    }
  }

  private static let proButtonTable: [(UInt32, Control)] = [
    (0x0000_0008, .east), (0x0000_0004, .south), (0x0000_0002, .north),
    (0x0000_0001, .west), (0x0040_0000, .leftShoulder), (0x0000_0040, .rightShoulder),
    (0x0080_0000, .leftTrigger), (0x0000_0080, .rightTrigger), (0x0000_0100, .back),
    (0x0000_0200, .start), (0x0000_0800, .leftStickClick), (0x0000_0400, .rightStickClick),
    (0x0000_1000, .guide), (0x0000_2000, .capture),
  ]
  private static let leftJoyConButtonTable: [(UInt32, Control)] =
    [(0x0020_0000, .auxiliary3), (0x0010_0000, .auxiliary4)] + proButtonTable
  private static let rightJoyConButtonTable: [(UInt32, Control)] =
    [(0x0000_0020, .auxiliary5), (0x0000_0010, .auxiliary6)] + proButtonTable

  /// Every request of the description in order; the SPI reads join the pending set.
  private func startupReports() -> [PhysicalHIDOutputReport] {
    pendingMotionCalibration = Set(subcommands.requests.compactMap { $0.spiRead?.purpose })
    factoryMotionBytes = nil
    userMotionBytes = nil
    return subcommands.requests.map { subcommand($0.subcommand, data: $0.data) }
  }

  public func startupRecoveryWrites() -> [PhysicalOutputWrite] {
    pendingMotionCalibrationRequests().map { .hidOutput($0) }
  }

  /// The SPI reads whose reply has not arrived, in the description's order.
  private func pendingMotionCalibrationRequests() -> [PhysicalHIDOutputReport] {
    subcommands.requests
      .filter { $0.spiRead.map { pendingMotionCalibration.contains($0.purpose) } ?? false }
      .map { subcommand($0.subcommand, data: $0.data) }
  }

  public func expireStartupRecovery() {
    pendingMotionCalibration.removeAll()
    factoryMotionBytes = nil
    userMotionBytes = nil
  }

  private func consumeMotionCalibrationReply(_ bytes: [UInt8]) {
    guard bytes.count >= 20, bytes[13] & 0x80 != 0 else { return }
    let address =
      UInt32(bytes[15]) | (UInt32(bytes[16]) << 8) | (UInt32(bytes[17]) << 16)
      | (UInt32(bytes[18]) << 24)
    guard
      let request = subcommands.requests.first(where: {
        $0.subcommand == bytes[14] && $0.spiRead?.address == address
      }),
      let read = request.spiRead, pendingMotionCalibration.contains(read.purpose)
    else { return }
    let length = Int(read.length)
    guard Int(bytes[19]) == length, bytes.count >= 20 + length else { return }
    let data = Array(bytes[20..<(20 + length)])
    if read.purpose == .factoryMotionCalibration {
      guard NintendoMotionCalibration.factory(data) != nil else { return }
      factoryMotionBytes = data
    } else {
      userMotionBytes = data[0] == 0xB2 && data[1] == 0xA1 ? data : nil
    }
    pendingMotionCalibration.remove(read.purpose)
    guard let factoryMotionBytes,
      let factory = NintendoMotionCalibration.factory(factoryMotionBytes)
    else { return }
    let calibrated =
      userMotionBytes.flatMap {
        NintendoMotionCalibration.factory(factoryMotionBytes, userOffsets: $0)
      } ?? factory
    motionCalibration = calibrated.installed(after: motionCalibration)
  }

  private func subcommand(_ id: UInt8, data: [UInt8]) -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: 11 + data.count)
    bytes[0] = subcommands.reportID
    bytes[1] = nextPacketNumber()
    bytes.replaceSubrange(2..<10, with: physicalRumbleData)
    bytes[10] = id
    for (index, value) in data.enumerated() { bytes[11 + index] = value }
    return PhysicalHIDOutputReport(reportID: subcommands.reportID, bytes: bytes)
  }

  private func nextPacketNumber() -> UInt8 {
    defer { outputPacketNumber = subcommands.nextCounter(after: outputPacketNumber) }
    return outputPacketNumber
  }

  private func readUInt24LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16)
  }

  private func readStick(_ bytes: [UInt8], offset: Int) -> (x: UInt16, y: UInt16) {
    let x = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1] & 0x0F) << 8)
    let y = (UInt16(bytes[offset + 1]) >> 4) | (UInt16(bytes[offset + 2]) << 4)
    return (x, y)
  }

  private func normalizeStick(_ value: UInt16) -> Float {
    let centered = Float(Int(value) - Int(switchProStickCenter)) / switchProStickMax
    return max(-1, min(1, centered))
  }

  private func mapDpad(up: Bool, right: Bool, down: Bool, left: Bool) -> HatDirection {
    switch (up, right, down, left) {
    case (true, false, false, false): return .north
    case (true, true, false, false): return .northEast
    case (false, true, false, false): return .east
    case (false, true, true, false): return .southEast
    case (false, false, true, false): return .south
    case (false, false, true, true): return .southWest
    case (false, false, false, true): return .west
    case (true, false, false, true): return .northWest
    default: return .neutral
    }
  }
}
