#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    var accessibilityValue: String {
      let details = OJDLocalized.formatted(
        "controllers.accessibilityDetails",
        connectionValue.spokenText,
        profileAccessibilityValue,
        device.protocolBinding.displayName,
        OJDValue.reported(device.protocolBinding.commandLineName).spokenText,
        serialVisibility.presentation(of: ControllerDetailFacts.serialNumber(device)).spokenText,
        ControllerDetailFacts.usbIdentifier(device).spokenText,
        OJDValue.endpoint(device.inputEndpoint).spokenText,
        OJDValue.endpoint(device.outputEndpoint).spokenText
      )
      let battery = OJDLocalized.formatted(
        "controllers.batteryAccessibilityDetails",
        ControllerDetailFacts.battery(device).spokenText,
        ControllerDetailFacts.chargingState(device).spokenText,
        ControllerDetailFacts.cableState(device).spokenText
      )
      return "\(details) \(battery)"
    }

    private var profileAccessibilityValue: String {
      switch activeProfile {
      case .loading:
        return OJDLocalized.string(
          "controllers.profileCheckingSentence"
        )
      case .noProfile:
        return OJDLocalized.string(
          "controllers.noActiveProfileSentence"
        )
      case .profile(let name):
        return OJDLocalized.formatted(
          "controllers.activeProfileSentence",
          name
        )
      case .unavailable(let message):
        return OJDLocalized.formatted(
          "controllers.profileUnavailableSentence",
          message
        )
      case .error(let message):
        return OJDLocalized.formatted(
          "controllers.profileErrorSentence",
          message
        )
      }
    }
  }

#endif
