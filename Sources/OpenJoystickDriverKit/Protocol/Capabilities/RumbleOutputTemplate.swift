/// One HID report a controller record names by kind, report ID and byte length. The length
/// counts the report-ID byte, which leads the report when the ID is nonzero.
public struct ControllerTemplateReport: Hashable, Sendable {
  /// `output` or `feature`; a record never writes an input report.
  public let kind: PhysicalHIDReportKind
  public let reportID: UInt8
  public let length: Int

  /// The byte offsets a template may set: every byte after a nonzero report ID.
  var writableBytes: Range<Int> { (reportID == 0 ? 0 : 1)..<length }

  init(kind: PhysicalHIDReportKind, reportID: UInt8, length: Int) {
    self.kind = kind
    self.reportID = reportID
    self.length = length
  }
}

/// How a template writes one motor's intensity into its bytes.
public enum RumbleMotorEncoding: String, CaseIterable, Sendable {
  /// One byte, the intensity as 0–255.
  case uInt8 = "UInt8"
  /// Two bytes, the intensity as 0–65535, high byte first.
  case uInt16BigEndian = "UInt16BigEndian"
  /// Two bytes, the intensity as 0–65535, low byte first.
  case uInt16LittleEndian = "UInt16LittleEndian"
  /// Four bytes of Switch HD rumble at the default 160/320 Hz frequencies.
  case switchHDRumble = "SwitchHDRumble"

  /// How many bytes one value takes.
  var width: Int {
    switch self {
    case .uInt8: 1
    case .uInt16BigEndian, .uInt16LittleEndian: 2
    case .switchHDRumble: 4
    }
  }

  /// The bytes of `intensity`.
  func bytes(_ intensity: UnipolarValue) -> [UInt8] {
    let wide = intensity.rawValue
    switch self {
    case .uInt8: return [intensity.byte]
    case .uInt16BigEndian: return [UInt8(wide >> 8), UInt8(wide & 0xFF)]
    case .uInt16LittleEndian: return [UInt8(wide & 0xFF), UInt8(wide >> 8)]
    case .switchHDRumble: return SwitchProRumbleCodec.encode(intensity: intensity.byte)
    }
  }
}

/// A controller's rumble report: fixed bytes with one encoded intensity per motor and, for a
/// family that numbers its output reports, the session's rolling counter. It drives a rumble
/// report without code of its own for the report's layout.
public struct RumbleOutputTemplate: Equatable, Sendable {
  /// Motors a template may name. Trackpad haptics belong to the Steam drivers.
  static let templateMotors: [PhysicalRumbleMotor] = [
    .leftMain, .rightMain, .leftTrigger, .rightTrigger,
  ]
  /// The resend intervals a template may name, as a keep-alive's.
  static let resendIntervalRange = KeepAlive.intervalRange

  /// Where the template's bytes go.
  public enum Target: Hashable, Sendable {
    /// A HID output or feature report.
    case hid(ControllerTemplateReport)
    /// A raw-USB packet of `length` bytes to the family's output endpoint.
    case usb(length: Int)

    var length: Int {
      switch self {
      case .hid(let report): report.length
      case .usb(let length): length
      }
    }

    /// The byte offsets a template may set.
    var writableBytes: Range<Int> {
      switch self {
      case .hid(let report): report.writableBytes
      case .usb(let length): 0..<length
      }
    }
  }

  /// Where one motor's intensity goes.
  public struct MotorField: Hashable, Sendable {
    /// The offset of the first byte.
    public let byte: Int
    public let encoding: RumbleMotorEncoding

    public init(byte: Int, encoding: RumbleMotorEncoding = .uInt8) {
      self.byte = byte
      self.encoding = encoding
    }

    var bytes: Range<Int> { byte..<(byte + encoding.width) }
  }

  public let target: Target
  /// Every byte of the report before the motors and counter are written; the report ID leads a
  /// numbered HID report.
  public let bytes: [UInt8]
  public let motors: [PhysicalRumbleMotor: MotorField]
  /// The byte that carries the session's rolling output counter; nil when the report has none.
  public let counterByte: Int?
  /// How often the last report is sent again while a motor runs; nil sends it once.
  public let resendIntervalMilliseconds: Int?

  /// The HID report this template writes; nil for a raw-USB packet.
  public var report: ControllerTemplateReport? { target.hidReport }

  /// Fails unless the target is an output or feature report or a raw-USB packet of an allowed
  /// length, `bytes` covers the whole report and starts with a nonzero report ID, at least one
  /// template motor is named, and the motor fields and the counter are disjoint writable bytes.
  init(
    target: Target,
    bytes: [UInt8]? = nil,
    motors: [PhysicalRumbleMotor: MotorField],
    counterByte: Int? = nil,
    resendIntervalMilliseconds: Int? = nil
  ) throws(ControllerRecordProblem) {
    switch target {
    case .hid(let report):
      guard report.kind != .input else {
        throw ControllerRecordProblem("a rumble template writes an output or feature report")
      }
      guard (2...64).contains(report.length) else {
        throw ControllerRecordProblem("a rumble report is 2...64 bytes long")
      }
    case .usb(let length):
      guard (1...64).contains(length) else {
        throw ControllerRecordProblem("a rumble packet is 1...64 bytes long")
      }
    }
    let base = bytes ?? Self.zeroedBytes(for: target)
    guard base.count == target.length else {
      throw ControllerRecordProblem("rumble template bytes must cover the whole report")
    }
    if let report = target.hidReport, report.reportID != 0, base[0] != report.reportID {
      throw ControllerRecordProblem("rumble template bytes must start with the report ID")
    }
    guard !motors.isEmpty, motors.keys.allSatisfy(Self.templateMotors.contains) else {
      throw ControllerRecordProblem("a rumble template names at least one motor")
    }
    let fields = motors.values.map(\.bytes) + (counterByte.map { [$0..<($0 + 1)] } ?? [])
    let writable = target.writableBytes
    let used = fields.flatMap { $0 }
    guard fields.allSatisfy({ writable.contains($0.lowerBound) && $0.upperBound <= writable.upperBound }),
      Set(used).count == used.count
    else {
      throw ControllerRecordProblem(
        "rumble motor and counter bytes must be distinct and follow the report ID inside the report"
      )
    }
    if let resendIntervalMilliseconds,
      !Self.resendIntervalRange.contains(resendIntervalMilliseconds)
    {
      throw ControllerRecordProblem("a rumble resend interval is 1...60000 milliseconds")
    }
    self.target = target
    self.bytes = base
    self.motors = motors
    self.counterByte = counterByte
    self.resendIntervalMilliseconds = resendIntervalMilliseconds
  }

  /// The bytes of a template that names none: zeros after the report ID of a numbered report.
  static func zeroedBytes(for target: Target) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: target.length)
    if let report = target.hidReport, report.reportID != 0 { bytes[0] = report.reportID }
    return bytes
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(rumbleMotors: Array(motors.keys))
  }

  /// The report bytes carrying these intensities and `counter`; motors the template does not
  /// name are dropped.
  func reportBytes(_ intensities: RumbleIntensities, counter: UInt8 = 0) -> [UInt8] {
    var bytes = self.bytes
    for (motor, field) in motors {
      bytes.replaceSubrange(field.bytes, with: field.encoding.bytes(intensities[motor]))
    }
    if let counterByte { bytes[counterByte] = counter }
    return bytes
  }

  /// Rumble through this HID template; the motors run until the next report.
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _): PhysicalOutputPlan(writes: [write(intensities)])
    case .stopRumble: PhysicalOutputPlan(writes: [write(.off)])
    default: throw .unsupportedCapability(command.capability)
    }
  }

  /// The HID report carrying these intensities. A raw-USB template has no HID report; its
  /// driver sends ``reportBytes(_:counter:)`` to its endpoint.
  func write(_ intensities: RumbleIntensities, counter: UInt8 = 0) -> PhysicalOutputWrite {
    guard let report else {
      preconditionFailure("a raw-USB rumble template is sent by its driver")
    }
    let hidReport = PhysicalHIDOutputReport(
      reportID: report.reportID,
      bytes: reportBytes(intensities, counter: counter)
    )
    return report.kind == .feature ? .hidFeature(hidReport) : .hidOutput(hidReport)
  }
}

extension RumbleOutputTemplate.Target {
  /// The HID report of a `hid` target; nil for a raw-USB packet.
  var hidReport: ControllerTemplateReport? {
    if case .hid(let report) = self { return report }
    return nil
  }
}
