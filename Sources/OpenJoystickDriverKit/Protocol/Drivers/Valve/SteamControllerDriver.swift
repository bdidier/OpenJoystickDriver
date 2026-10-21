import Foundation

let steamControllerReportPrefix0: UInt8 = 0x01
let steamControllerReportPrefix1: UInt8 = 0x00
let steamControllerStateMessageID: UInt8 = 0x01
let steamControllerWirelessMessageID: UInt8 = 0x03
let steamControllerStatusMessageID: UInt8 = 0x04
let steamControllerReportLength = 64
let steamControllerTriggerMax: Float = 255
let steamControllerStickMax: Float = 32767
let steamControllerWirelessDisconnected: UInt8 = 0x01
let steamControllerWirelessConnected: UInt8 = 0x02
let steamControllerSetSettingsValuesCommand: UInt8 = 0x87
let steamControllerGetWirelessStateCommand: UInt8 = 0xB4
let steamControllerHapticPulseCommand: UInt8 = 0x8F
let steamControllerHapticPulsePayloadLength: UInt8 = 8
let steamControllerUserLEDBrightnessSetting: UInt8 = 45
let steamControllerMaximumPulseMicroseconds = 65_535
/// The length of the pulse that stands for a held rumble, which the pad cannot hold open-ended.
let steamControllerHeldPulseMilliseconds = 65

/// Driver for Valve Steam Controller input reports.
///
/// Linux `hid-steam.c` receives 64-byte raw events prefixed with `0x01, 0x00`.
/// Message type `0x01` carries a 60-byte controller state payload with button
/// bytes at offsets 8-10, analog triggers at 11-12, left stick/left pad axes at
/// 16-19, and right pad axes at 20-23. Source-backed lizard-mode feature
/// reports are sent when OJD starts and stops consuming Steam Controller input. Over Bluetooth LE
/// the same messages travel in report-`0x03` segments (``SteamBluetooth``).
public final class SteamControllerDriver: PhysicalProtocolDriver {

  var motionSamples = SteamMotionSamples()
  var touchSamples = SteamTouchSamples()
  var state = ControllerState.neutral
  /// The left stick's last raw position, which a report interleaving pad and stick keeps.
  var leftStickRaw: (x: Int16, y: Int16) = (0, 0)
  let isWirelessReceiver: Bool
  /// The classic controller paired over Bluetooth LE: segmented report-`0x03` framing.
  let isBluetooth: Bool
  var bluetoothAssembler = SteamBluetoothAssembler()
  var bluetoothState = SteamBluetoothState()
  var isLogicalControllerConnected: Bool
  var pendingConnectionStateChange: ControllerInputConnectionState?

  /// Creates a new Steam Controller parser.
  public init(isWirelessReceiver: Bool = false, isBluetooth: Bool = false) {
    self.isWirelessReceiver = isWirelessReceiver
    self.isBluetooth = isBluetooth
    isLogicalControllerConnected = !isWirelessReceiver
  }

  /// A new transport session starts from neutral input and re-anchors motion time.
  public func resetProtocolState() {
    state = .neutral
    leftStickRaw = (0, 0)
    motionSamples.reset()
    bluetoothAssembler.reset()
    bluetoothState = SteamBluetoothState()
  }
}
