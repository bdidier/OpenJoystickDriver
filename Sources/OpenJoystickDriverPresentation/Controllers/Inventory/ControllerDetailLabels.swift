import Foundation
import OpenJoystickDriverKit

/// The localization key of each state the Controllers detail names. Every switch lists all cases,
/// so a new case fails to compile until it has text.
enum ControllerDetailLabels {
  /// The localization key of the reason a controller publishes no virtual device.
  static func notPublishedReasonKey(
    _ reason: ApplicationServicePublicationStatus.NotPublishedReason
  ) -> String {
    switch reason {
    case .outputDisabled: return "controllers.publication.reason.outputDisabled"
    case .systemGamepad: return "controllers.publication.reason.systemGamepad"
    case .nativeHIDPassThrough: return "controllers.publication.reason.nativeHIDPassThrough"
    case .upstreamVirtualDevice: return "controllers.publication.reason.upstreamVirtualDevice"
    case .sessionSuspended: return "controllers.publication.reason.sessionSuspended"
    case .noVirtualProfile: return "controllers.publication.reason.noVirtualProfile"
    case .suppressed: return "controllers.publication.reason.suppressed"
    case .noInputYet: return "controllers.publication.reason.noInputYet"
    }
  }

  static func servingReasonKey(_ reason: OutputDisabledReason) -> String {
    switch reason {
    case .userDisabled: return notPublishedReasonKey(.outputDisabled)
    case .upstreamVirtualDevice: return notPublishedReasonKey(.upstreamVirtualDevice)
    case .noVirtualProfile: return notPublishedReasonKey(.noVirtualProfile)
    }
  }

  static func inputHealthReasonKey(_ reason: ControllerInputHealthFailureReason) -> String {
    switch reason {
    case .missingReports: return "controllers.inputHealth.reason.missingReports"
    case .freshnessNotAdvancing: return "controllers.inputHealth.reason.freshnessNotAdvancing"
    }
  }

  static func discoveryKey(_ source: DeviceDiscoverySource) -> String {
    switch source {
    case .hid: return "controllers.discovery.hid"
    case .rawUSB: return "controllers.discovery.rawUSB"
    }
  }

  static func physicalOwnershipKey(_ ownership: ControllerOwnershipObservation) -> String {
    switch ownership {
    case .exclusiveHID: return "controllers.physicalOwnership.exclusiveHID"
    case .exclusiveRawUSB: return "controllers.physicalOwnership.exclusiveRawUSB"
    case .extensionOwnedUSB: return "controllers.physicalOwnership.extensionOwnedUSB"
    case .systemHIDVisible: return "controllers.physicalOwnership.systemHIDVisible"
    case .systemGamepad: return "controllers.physicalOwnership.systemGamepad"
    case .upstreamVirtualDevice: return "controllers.physicalOwnership.upstreamVirtualDevice"
    case .unknown: return "controllers.physicalOwnership.unknown"
    }
  }

  static func hidInputOwnershipKey(_ ownership: HIDInputOwnership) -> String {
    switch ownership {
    case .unknown: return "controllers.hidInputOwnership.unknown"
    case .exclusive: return "controllers.hidInputOwnership.exclusive"
    case .shared: return "controllers.hidInputOwnership.shared"
    case .accessDenied: return "controllers.hidInputOwnership.accessDenied"
    case .ownedByAnotherClient: return "controllers.hidInputOwnership.ownedByAnotherClient"
    case .acquisitionFailed: return "controllers.hidInputOwnership.acquisitionFailed"
    }
  }

  /// The failure of a wireless disconnect, localized. The stage, system code, and detail stay in
  /// the log and in `ojd controller disconnect`.
  static func wirelessDisconnectFailureText(
    _ failure: WirelessControllerDisconnectFailure
  ) -> String {
    let key: String
    switch failure {
    case .notFound: key = "controllers.disconnectWireless.failure.notFound"
    case .notBluetooth: key = "controllers.disconnectWireless.failure.notBluetooth"
    case .bluetoothLEUnsupported:
      key = "controllers.disconnectWireless.failure.bluetoothLEUnsupported"
    case .missingAddress: key = "controllers.disconnectWireless.failure.missingAddress"
    case .disconnectFailed: key = "controllers.disconnectWireless.failure.disconnectFailed"
    case .timedOut: key = "controllers.disconnectWireless.failure.timedOut"
    }
    return OJDLocalized.string(key)
  }
}
