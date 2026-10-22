import Foundation

/// Identifier of one exact published virtual HID ABI.
///
/// These are the only two personas OJD recognizes: `SDLCompatible` and `Generic`. Decoding any
/// other raw value fails.
public enum VirtualHIDProfileID: String, CaseIterable, Codable, Sendable {
  case sdlCompatible = "SDLCompatible"
  case generic = "Generic"

  /// The id of the persona on the command line: the lowercase kebab-case form of its name.
  public var commandLineName: String { CommandLineName.kebab(rawValue) }

  /// The profile this identifier names.
  public func makeProfile() throws -> any VirtualHIDProfile {
    switch VirtualDevice.definition(of: self).layout {
    case .xboxOneGIP?: return XboxOneGIPHIDProfile()
    case .ojdGenericGamepad?, nil: return OJDGenericHIDProfile()
    }
  }

  /// The identity the persona's `VirtualDevice` record publishes, readable without building its
  /// report format.
  public var identity: VirtualDeviceProfile {
    guard let profile = VirtualDevice.definition(of: self).profile else {
      fatalError("[VirtualDevice] \(rawValue) has no identity")
    }
    return profile
  }

  /// Whether SDL recognizes the persona with its default hints, as its definition states.
  public var worksWithDefaultSDLHints: Bool {
    guard let works = VirtualDevice.definition(of: self).worksWithDefaultSDLHints else {
      fatalError("[VirtualDevice] \(rawValue) does not state worksWithDefaultSDLHints")
    }
    return works
  }

  /// Every normalized control this profile's layout can carry, which is what profile selection
  /// checks a controller's required primary controls against.
  public var representableControls: Set<Control> {
    switch self {
    // The Xbox layout. Guide stays out until a genuine capture shows whether ordinary HID clients
    // see it, although today's report still carries it as button usage 11 of report 0x07.
    case .sdlCompatible: return Control.xboxLayout
    // The generic layout: the frozen 32 buttons, the hat and the six named axes. Today's report
    // carries only its first 16 buttons.
    case .generic:
      return Control.dpad.union([
        .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
        .back, .start, .leftStickClick, .rightStickClick, .guide, .capture, .touchpadClick,
        .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2, .auxiliary1, .auxiliary2,
        .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8,
        .leftStickTouch, .rightStickTouch, .leftTrackpadClick, .rightTrackpadClick, .leftStickX,
        .leftStickY, .rightStickX, .rightStickY,
      ])
    }
  }
}

/// One exact virtual HID ABI: the published identity, the report descriptor, and the codec
/// between the normalized model and that descriptor's reports.
public protocol VirtualHIDProfile: Sendable {
  var id: VirtualHIDProfileID { get }

  /// Identity properties the publisher sets: vendor and product IDs, version, product and
  /// manufacturer strings, and the virtual transport. The per-controller serial is not part of
  /// the profile.
  var identity: VirtualDeviceProfile { get }

  /// Complete HID report descriptor bytes.
  var descriptor: [UInt8] { get }

  /// The report format this approximation wraps, which the user-space publisher composes with
  /// `identity`.
  var reportFormat: any VirtualGamepadReportFormat { get }

  /// The complete input report, including its report ID byte, for `state`.
  func inputReport(for state: ControllerState) -> [UInt8]

  /// Decodes a consumer's output report, as delivered with its report ID byte, into the command
  /// it requests; nil when the report is not one this profile declares, or is malformed.
  func consumerOutput(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> ControllerOutputCommand?
}

/// `SDLCompatible` over today's hand-authored approximation, not a verified Microsoft ABI.
///
/// The identity is the `SDLCompatible` `VirtualDevice` record's. The descriptor and input layout
/// are `XboxOneGIPHIDReportFormat`'s: Xbox One GIP packets as numbered reports, the form SDL's
/// HIDAPI Xbox One driver parses for a device whose IOHID transport is not `Bluetooth`. The d-pad
/// is four state bits, and share is never set. It is an approximation until the descriptor and
/// codec are replaced byte-exactly from a genuine capture.
struct XboxOneGIPHIDProfile: VirtualHIDProfile {
  let id = VirtualHIDProfileID.sdlCompatible
  private let format: XboxOneGIPHIDReportFormat

  init() { format = XboxOneGIPHIDReportFormat() }

  var identity: VirtualDeviceProfile { id.identity }
  var descriptor: [UInt8] { format.descriptor }
  var reportFormat: any VirtualGamepadReportFormat { format }

  func inputReport(for state: ControllerState) -> [UInt8] {
    ReportFormatCodec.inputReport(for: state, in: format)
  }

  func consumerOutput(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> ControllerOutputCommand? {
    ReportFormatCodec.consumerOutput(type: type, reportID: reportID, bytes: bytes, in: format)
  }
}

/// `Generic` over the OJD generic gamepad, an approximation of the specified ABI.
///
/// The identity is the `Generic` `VirtualDevice` record's, and the
/// descriptor is `OJDGenericGamepadFormat`'s input-only layout: 16 buttons with the d-pad as four
/// of them, no hat, four stick axes and two trigger axes, and no output report, so the profile
/// decodes no consumer output. pid.codes allocated the ID.
struct OJDGenericHIDProfile: VirtualHIDProfile {
  let id = VirtualHIDProfileID.generic
  private let format = OJDGenericGamepadFormat()

  var identity: VirtualDeviceProfile { id.identity }
  var descriptor: [UInt8] { format.descriptor }
  var reportFormat: any VirtualGamepadReportFormat { format }

  func inputReport(for state: ControllerState) -> [UInt8] {
    ReportFormatCodec.inputReport(for: state, in: format)
  }

  func consumerOutput(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) -> ControllerOutputCommand? { nil }
}

/// The adapter from a profile's contract to the report format it wraps.
private enum ReportFormatCodec {
  /// Encodes canonical state through the dispatcher's mapping, without its stick dead zone,
  /// which is output policy rather than part of the ABI.
  static func inputReport(
    for state: ControllerState,
    in format: some VirtualGamepadReportFormat
  ) -> [UInt8] {
    var virtual = VirtualGamepadState()
    VirtualGamepadReportMapping.apply(
      state,
      stickTransfer: .init(deadzone: 0, rescalesDeadzone: false),
      to: &virtual
    )
    return format.buildInputReport(from: virtual)
  }

  /// Decodes an output report through the consumer output codec that the published device's
  /// set-report callback uses.
  static func consumerOutput(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8],
    in format: some VirtualGamepadReportFormat
  ) -> ControllerOutputCommand? {
    guard type == .output,
      let request = try? VirtualHostReportRequest(type: .output, reportID: reportID, bytes: bytes)
    else { return nil }
    return try? ConsumerOutputCodec.decode(request, in: format)
  }
}
