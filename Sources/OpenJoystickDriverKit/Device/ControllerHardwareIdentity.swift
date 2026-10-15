import Foundation

/// The model and physical identity of a controller: its model ID and serial number.
///
/// Two identities with the same non-nil serial number name the same physical device, whichever
/// link, location or interface it is reached through. Without a serial number an identity names
/// only the model, which all controllers of that model share.
public struct ControllerHardwareIdentity: Hashable, Sendable {
  /// The vendor ID and product ID.
  public let model: ControllerModelID
  /// Serial number reported by the controller.
  ///
  /// Nil if the controller does not provide one; an empty serial is stored as nil.
  public let serialNumber: String?

  /// Creates the identity of `model` with `serialNumber`.
  public init(model: ControllerModelID, serialNumber: String? = nil) {
    self.model = model
    self.serialNumber = serialNumber?.isEmpty == false ? serialNumber : nil
  }

  /// Whether this identity names one physical device rather than every unit of its model.
  public var identifiesPhysicalDevice: Bool { serialNumber != nil }
}
