import OpenJoystickDriverKit

extension ApplicationServiceDeviceDescription {
  /// Whether the service can close the controller's wireless link, from the typed transport it
  /// reports. Only a classic Bluetooth link has a disconnect path; a controller that reports no
  /// transport has none.
  var supportsWirelessDisconnect: Bool { connectionState?.transport == .bluetoothClassic }
}
