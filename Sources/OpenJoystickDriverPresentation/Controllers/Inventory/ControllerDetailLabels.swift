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
    case .outputDisabled: return "ui.controllers.publication.reason.outputDisabled"
    case .systemGamepad: return "ui.controllers.publication.reason.systemGamepad"
    case .nativeHIDPassThrough: return "ui.controllers.publication.reason.nativeHIDPassThrough"
    case .upstreamVirtualDevice: return "ui.controllers.publication.reason.upstreamVirtualDevice"
    case .sessionSuspended: return "ui.controllers.publication.reason.sessionSuspended"
    case .noVirtualProfile: return "ui.controllers.publication.reason.noVirtualProfile"
    case .suppressed: return "ui.controllers.publication.reason.suppressed"
    case .noInputYet: return "ui.controllers.publication.reason.noInputYet"
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
    case .missingReports: return "ui.controllers.inputHealth.reason.missingReports"
    case .freshnessNotAdvancing: return "ui.controllers.inputHealth.reason.freshnessNotAdvancing"
    case .guideNotPressed: return "ui.controllers.inputHealth.reason.guideNotPressed"
    }
  }

  static func discoveryKey(_ source: DeviceDiscoverySource) -> String {
    switch source {
    case .hid: return "ui.controllers.discovery.hid"
    case .rawUSB: return "ui.controllers.discovery.rawUSB"
    }
  }

  static func physicalOwnershipKey(_ ownership: ControllerOwnershipObservation) -> String {
    switch ownership {
    case .exclusiveHID: return "ui.controllers.physicalOwnership.exclusiveHID"
    case .exclusiveRawUSB: return "ui.controllers.physicalOwnership.exclusiveRawUSB"
    case .extensionOwnedUSB: return "ui.controllers.physicalOwnership.extensionOwnedUSB"
    case .systemHIDVisible: return "ui.controllers.physicalOwnership.systemHIDVisible"
    case .systemGamepad: return "ui.controllers.physicalOwnership.systemGamepad"
    case .upstreamVirtualDevice: return "ui.controllers.physicalOwnership.upstreamVirtualDevice"
    case .unknown: return "ui.controllers.physicalOwnership.unknown"
    }
  }

  static func hidInputOwnershipKey(_ ownership: HIDInputOwnership) -> String {
    switch ownership {
    case .unknown: return "ui.controllers.hidInputOwnership.unknown"
    case .exclusive: return "ui.controllers.hidInputOwnership.exclusive"
    case .shared: return "ui.controllers.hidInputOwnership.shared"
    case .accessDenied: return "ui.controllers.hidInputOwnership.accessDenied"
    case .ownedByAnotherClient: return "ui.controllers.hidInputOwnership.ownedByAnotherClient"
    case .acquisitionFailed: return "ui.controllers.hidInputOwnership.acquisitionFailed"
    }
  }

  /// The failure of a wireless disconnect, localized. The stage, system code, and detail stay in
  /// the log and in `ojd controller disconnect`.
  static func wirelessDisconnectFailureText(
    _ failure: WirelessControllerDisconnectFailure
  ) -> String {
    let key: String
    switch failure {
    case .notFound: key = "ui.controllers.disconnectWireless.failure.notFound"
    case .notBluetooth: key = "ui.controllers.disconnectWireless.failure.notBluetooth"
    case .bluetoothLEUnsupported:
      key = "ui.controllers.disconnectWireless.failure.bluetoothLEUnsupported"
    case .missingAddress: key = "ui.controllers.disconnectWireless.failure.missingAddress"
    case .disconnectFailed: key = "ui.controllers.disconnectWireless.failure.disconnectFailed"
    case .timedOut: key = "ui.controllers.disconnectWireless.failure.timedOut"
    }
    return OJDLocalized.string(key)
  }
}
