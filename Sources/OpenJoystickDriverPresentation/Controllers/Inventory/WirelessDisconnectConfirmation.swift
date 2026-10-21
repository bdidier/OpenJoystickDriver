import Foundation

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
