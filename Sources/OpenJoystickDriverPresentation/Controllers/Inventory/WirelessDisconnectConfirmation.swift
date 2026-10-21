import Foundation
import OpenJoystickDriverKit

/// The text of the confirmation that precedes closing a controller's Bluetooth link, shown by the
/// Controller menu, the status menu and the controller list.
struct WirelessDisconnectConfirmation: Equatable {
  let title: String
  let message: String
  let confirmTitle: String

  init(controllerName: String) {
    title = OJDLocalized.string("controllers.disconnectWirelessConfirmTitle")
    message = OJDLocalized.formatted(
      "controllers.disconnectWirelessConfirmMessage",
      controllerName
    )
    confirmTitle = OJDLocalized.string("controllers.disconnectWirelessConfirm")
  }
}

/// A pending Bluetooth link closure: the controller captured when the user asked, so the
/// confirmed action still has it after the presentation state has been reset.
struct WirelessDisconnectRequest: Identifiable {
  let device: ApplicationServiceDeviceDescription
  let confirmation: WirelessDisconnectConfirmation

  var id: String { device.sessionToken.rawValue }

  init(device: ApplicationServiceDeviceDescription) {
    self.device = device
    confirmation = WirelessDisconnectConfirmation(controllerName: device.name)
  }
}
