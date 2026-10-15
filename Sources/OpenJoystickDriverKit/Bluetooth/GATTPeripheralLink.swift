import Foundation

/// The `coreBluetoothGATT` link of one Switch 2 controller: it carries notifications from a
/// ``GATTPeripheral`` into the hub as input and command-reply frames, and carries the hub's
/// writes back to the peripheral's command and vibration characteristics.
///
/// The owner of the peripheral calls ``admit()`` once the input and reply notifications are
/// enabled, ``notified(characteristic:value:)`` for each notification, and ``disconnected()``
/// when the peripheral goes.
public final class GATTPeripheralLink: Switch2BluetoothLEWriter, Sendable {
  public let peripheral: any GATTPeripheral
  public let productID: UInt16
  public let productName: String?
  private let hub: Switch2BluetoothLEHub
  private let commandUUID: String
  private let vibrationUUID: String

  /// Returns nil when no controller record of `productID` declares a vibration characteristic.
  public init?(
    peripheral: any GATTPeripheral,
    productID: UInt16,
    productName: String?,
    hub: Switch2BluetoothLEHub
  ) {
    guard let vibrationUUID = Switch2BluetoothLEProfile.vibrationUUID(productID: productID)
    else { return nil }
    self.peripheral = peripheral
    self.productID = productID
    self.productName = productName
    self.hub = hub
    self.commandUUID = Switch2BluetoothLEProfile.commandUUID
    self.vibrationUUID = vibrationUUID
  }

  /// Presents the peripheral to the hub as a connected controller.
  public func admit() {
    hub.linkConnected(
      peripheralID: peripheral.identifier,
      productID: productID,
      productName: productName,
      writer: self
    )
  }

  /// Delivers one notification. Input frames and command replies reach the hub; any other
  /// characteristic is ignored.
  public func notified(characteristic: String, value: [UInt8]) {
    switch characteristic.uppercased() {
    case Switch2BluetoothLEProfile.inputUUID:
      hub.receivedInput(peripheralID: peripheral.identifier, bytes: value)
    case Switch2BluetoothLEProfile.commandReplyUUID:
      hub.receivedReply(peripheralID: peripheral.identifier, bytes: value)
    default:
      break
    }
  }

  public func disconnected() { hub.linkDisconnected(peripheralID: peripheral.identifier) }

  public func writeCommand(_ bytes: [UInt8]) -> Bool {
    peripheral.writeWithoutResponse(bytes, to: commandUUID)
  }

  public func writeVibration(_ bytes: [UInt8]) -> Bool {
    peripheral.writeWithoutResponse(bytes, to: vibrationUUID)
  }
}
