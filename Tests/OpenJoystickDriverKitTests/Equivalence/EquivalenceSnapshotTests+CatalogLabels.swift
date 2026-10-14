import Foundation

@testable import OpenJoystickDriverKit

/// Stable snapshot labels for catalog enums. Each label is a string written here, so renaming a
/// Swift case, a family, a protocol id, or a quirk changes only the switch below, not the
/// snapshot text of every record. A new case fails to compile until it gets a label.
extension EquivalenceSnapshotCatalogTests {
  static func label(_ id: PhysicalProtocolID) -> String {
    switch id {
    case .hidDescriptor: "hid-descriptor"
    case .hidReportLayout: "hid-report-layout"
    case .xboxXID: "xbox-xid"
    case .xboxXUSB: "xbox-xusb"
    case .xboxGIP: "xbox-gip"
    case .sonySixaxis: "sony-sixaxis"
    case .sonyDualShock4: "sony-dualshock4"
    case .sonyDualSense: "sony-dualsense"
    case .nintendoSwitch1: "nintendo-switch1"
    case .valveSteamController: "valve-steam-controller"
    case .vendorFlydigi: "vendor-flydigi"
    case .vendorPS3ThirdParty: "vendor-ps3-third-party"
    case .vendorGameSir: "vendor-gamesir"
    case .vendorNVIDIAShield: "vendor-nvidia-shield"
    }
  }

  static func label(_ variant: PhysicalProtocolVariantID?) -> String {
    switch variant {
    case nil: "-"
    case .usb?: "usb"
    case .bluetoothClassic?: "bluetooth-classic"
    case .bluetoothLE?: "bluetooth-le"
    case .gamepad?: "gamepad"
    case .wired?: "wired"
    case .receiver?: "receiver"
    case .dongle?: "dongle"
    case .enhancedHID?: "enhanced-hid"
    }
  }

  static func label(_ ownership: ControllerOwnership) -> String {
    switch ownership {
    case .macOS: "macos"
    case .ojd: "ojd"
    }
  }

  static func label(_ policy: GIPKeepAlivePolicy) -> String {
    switch policy {
    case .enabled: "enabled"
    case .disabled: "disabled"
    }
  }

  static func label(_ kind: PhysicalHIDReportKind) -> String {
    switch kind {
    case .input: "input"
    case .output: "output"
    case .feature: "feature"
    }
  }

  static func label(_ transport: PhysicalTransport?) -> String {
    switch transport {
    case nil: "all"
    case .usb?: "usb"
    case .bluetoothClassic?: "bluetooth-classic"
    case .bluetoothLE?: "bluetooth-le"
    case .proprietaryRadioReceiver?: "radio-receiver"
    }
  }

  static func label(_ key: ControllerTuning.Key) -> String {
    switch key {
    case .stickDeadzone: "stickDeadzone"
    case .inputLivenessTimeoutMs: "inputLivenessTimeoutMs"
    case .hidStartupRecoveryIntervalMs: "hidStartupRecoveryIntervalMs"
    case .hidStartupRecoveryRounds: "hidStartupRecoveryRounds"
    case .hidStartupIntervalMs: "hidStartupIntervalMs"
    case .minimumHIDOutputIntervalMs: "minimumHIDOutputIntervalMs"
    }
  }

  static func label(_ motor: PhysicalRumbleMotor) -> String {
    switch motor {
    case .leftMain: "left-main"
    case .rightMain: "right-main"
    case .leftTrigger: "left-trigger"
    case .rightTrigger: "right-trigger"
    case .leftHaptic: "left-haptic"
    case .rightHaptic: "right-haptic"
    }
  }

  static func label(_ feature: PhysicalLightingFeature) -> String {
    switch feature {
    case .playerIndicator: "player-indicator"
    case .programmableColor: "programmable-color"
    case .programmableBrightness: "programmable-brightness"
    }
  }

  static func label(_ trigger: PhysicalAdaptiveTrigger) -> String {
    switch trigger {
    case .left: "left"
    case .right: "right"
    }
  }

  static func label(_ quirk: ControllerQuirk) -> String {
    switch quirk {
    case .shareOffset: "share-offset"
    case .joyConLeft: "joy-con-left"
    case .joyConRight: "joy-con-right"
    case .inputOnly: "input-only"
    case .bluetoothOnly: "bluetooth-only"
    case .switch2: "switch-2"
    case .gameCube: "gamecube"
    case .innerGrips: "inner-grips"
    case .lightingSlots: "lighting-slots"
    case .triton: "triton"
    case .neptune: "neptune"
    case .dpadPressure: "dpad-pressure"
    case .factoryCalibration: "factory-calibration"
    case .wirelessAdapter: "wireless-adapter"
    case .strikePad: "strike-pad"
    case .shield2015: "shield-2015"
    case .wr007: "wr007"
    case .scufEnvision: "scuf-envision"
    case .zRzBrakeLeft: "zr-z-brake-left"
    case .dragonRise: "dragon-rise"
    case .thirdParty: "third-party"
    case .unprobedSensors: "unprobed-sensors"
    case .unprobedTouchpad: "unprobed-touchpad"
    case .forcedVibration: "forced-vibration"
    case .receiver: "receiver"
    }
  }

  /// Control ids are the persisted profile identifiers, so their raw values are the labels.
  static func labels(_ controls: Set<ControlID>) -> String {
    controls.map(\.rawValue).sorted().joined(separator: ",")
  }

  static func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined()
  }
}
