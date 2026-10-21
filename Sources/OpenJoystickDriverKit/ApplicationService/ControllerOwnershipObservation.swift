import Foundation

/// How OJD owns or observes the physical controller input path.
public enum ControllerOwnershipObservation: String, Codable, CaseIterable, Equatable, Sendable {
  case exclusiveHID
  case exclusiveRawUSB
  case extensionOwnedUSB = "ExtensionOwnedUSB"
  case systemHIDVisible = "SystemHIDVisible"
  /// macOS serves the controller as a native gamepad; OJD only observes its shared input.
  case systemGamepad = "SystemGamepad"
  case upstreamVirtualDevice
  case unknown

  /// Whether the system serves the controller itself, so OJD publishes no virtual device for it.
  /// The decision depends on who serves the input, not on which OS does.
  public var isServedBySystem: Bool {
    switch self {
    case .systemGamepad, .systemHIDVisible: true
    case .exclusiveHID, .exclusiveRawUSB, .extensionOwnedUSB, .upstreamVirtualDevice, .unknown:
      false
    }
  }
}

/// The duplicate-device concern associated with the physical ownership observation.
public enum DuplicateExposureRisk: String, Codable, Equatable, Sendable {
  case none
  case systemHIDVisible = "SystemHIDVisible"
  case upstreamVirtualDevice
  case unknownOwnership

}

extension DuplicateExposureRisk {
  /// The duplicate-device concern of one physical ownership observation.
  public init(observation: ControllerOwnershipObservation) {
    self =
      switch observation {
      // OJD never publishes for a native gamepad, so games see only Apple's device.
      case .exclusiveHID, .exclusiveRawUSB, .extensionOwnedUSB, .systemGamepad: .none
      case .systemHIDVisible: .systemHIDVisible
      case .upstreamVirtualDevice: .upstreamVirtualDevice
      case .unknown: .unknownOwnership
      }
  }
}
