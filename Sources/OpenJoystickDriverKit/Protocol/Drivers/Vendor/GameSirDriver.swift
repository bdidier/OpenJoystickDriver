import Foundation

let gameSirReportLength = 64
/// The spacing of lighting commands: the description's default output interval.
let gameSirCommandIntervalNanoseconds =
  DriverSessionPlan().withDefaults(of: .vendorGameSir).minimumHIDOutputIntervalNanoseconds

/// GameSir protocol families backed by the vendor's observed report streams.
public enum GameSirProtocol: Sendable, Equatable {
  case g7ProUSB
  case enhancedHID
}

/// Driver for source-backed GameSir controller identities.
public final class GameSirDriver: PhysicalProtocolDriver {
  let gameSirProtocol: GameSirProtocol
  /// Enhanced HID extras report the inner grips (parameter `innerGrips`).
  let hasInnerGrips: Bool
  /// Enhanced HID lighting memory is slot-based (parameter `lightingMemory: ProfileSlots`).
  let usesLightingSlots: Bool
  let outEndpoint: UInt8
  /// The enhanced HID rumble report. The wired G7 Pro encodes it too but advertises no rumble.
  let rumbleTemplate: RumbleOutputTemplate
  /// Raw-USB command timeout (`usbCommandTimeoutMs`).
  let usbTimeoutMilliseconds: UInt32
  var standardParser = XUSBDriver()
  var state = ControllerState.neutral
  /// The wired G7 splits input over two streams, standard XUSB reports and telemetry; each applies
  /// only the controls it changed, measured against its own last decode.
  var standardState = ControllerState.neutral
  var telemetryExtras = ControllerState.neutral
  var sequence: UInt8 = 0
  var sessionReady = false
  var activeLightingSlot: UInt8?
  var lightingBrightness: UInt8 = 100
  var storedPower: ControllerConnectionState.Power?

  /// - Parameters:
  ///   - outEndpoint: Interrupt OUT endpoint of the bound USB interface, for keep-alive and
  ///     brightness.
  ///   - rumbleTemplate: The record's rumble template; the description's for enhanced HID when
  ///     nil.
  public init(
    protocol gameSirProtocol: GameSirProtocol,
    hasInnerGrips: Bool = false,
    usesLightingSlots: Bool = false,
    outEndpoint: UInt8 = 0x02,
    tuning: ControllerTuning? = nil,
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    self.gameSirProtocol = gameSirProtocol
    self.hasInnerGrips = hasInnerGrips
    self.usesLightingSlots = usesLightingSlots
    self.outEndpoint = outEndpoint
    self.rumbleTemplate = PhysicalProtocolID.vendorGameSir.describedRumbleTemplate(
      variant: .enhancedHID,
      record: rumbleTemplate
    )
    usbTimeoutMilliseconds = UInt32(
      PhysicalProtocolID.vendorGameSir.described(\.usbCommandTimeoutMilliseconds, in: tuning)
    )
  }
}
