import Foundation

/// One controller in `ojd controller list --json` and in the object of watch lines.
///
/// The serial number is never printed; `hasSerialNumber` says whether the controller reports one.
public struct ControllerSummary: Encodable, Equatable, Sendable {
  /// The session token; see ``ControllerSessionToken``.
  public let id: String
  /// The port key; see ``ControllerPortKey``.
  public let unit: String?
  public let name: String
  public let vendorID: Int
  public let productID: Int
  public let connection: String
  public let `protocol`: String
  public let session: String
  public let hasSerialNumber: Bool
  /// Whether another client holds the controller's USB interface exclusively.
  public let ownedByAnotherClient: Bool
  /// The client that holds it; absent when none does or the interface names none.
  public let owner: USBExclusiveOwner?
  /// Absent when the service reports no power state.
  public let power: ControllerConnectionState.Power?

  public init(_ device: ApplicationServiceDeviceDescription) {
    id = device.sessionToken.rawValue
    unit = device.portKey?.rawValue
    name = device.name
    vendorID = Int(device.vendorID)
    productID = Int(device.productID)
    connection = device.connection
    self.protocol = device.protocolBinding.rawValue
    session = device.sessionState.rawValue
    hasSerialNumber = device.serialNumber.map { !$0.isEmpty } ?? false
    ownedByAnotherClient = device.hidInputOwnership == .ownedByAnotherClient
    owner = device.inputOwner
    power = device.connectionState?.power
  }
}
