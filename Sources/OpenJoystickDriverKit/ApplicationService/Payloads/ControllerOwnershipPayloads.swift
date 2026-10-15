import Foundation

/// Arguments of `setControllerOwnership`: the controller model and who serves it, `macos` or
/// `ojd`.
public struct LocalServiceRPCControllerOwnershipArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let ownership: ControllerServer

  public init(vendorID: Int, productID: Int, ownership: ControllerServer) {
    self.vendorID = vendorID
    self.productID = productID
    self.ownership = ownership
  }
}

/// Why a `setControllerOwnership` request changed nothing. The user record stays as it was.
public enum ControllerOwnershipFailure: String, Codable, Equatable, Sendable {
  /// The model's family uses raw USB, so OJD always serves it.
  case rawUSB
  /// macOS does not serve the model natively, so OJD always serves it.
  case notNative
  /// Neither the user directory, the bundled catalog, nor an installed package has a record of
  /// the model, so there is nothing to patch.
  case noRecord
  /// The existing user record, or the record with the new `ownership`, is invalid.
  case invalidRecord
  /// The user record cannot be written.
  case persistenceFailed
}

/// Result of `setControllerOwnership`.
public struct ControllerOwnershipResult: Codable, Equatable, Sendable {
  /// The ownership the request asked for.
  public let ownership: ControllerServer
  /// The model's effective ownership before the request.
  public let previous: ControllerServer
  /// The user record the request writes; nil when it was refused before a file was chosen.
  public let file: String?
  /// Whether the request created the user record.
  public let created: Bool
  public let failure: ControllerOwnershipFailure?
  /// The problem text of `invalidRecord` or `persistenceFailed`.
  public let detail: String?

  public init(
    ownership: ControllerServer,
    previous: ControllerServer,
    file: String?,
    created: Bool,
    failure: ControllerOwnershipFailure?,
    detail: String? = nil
  ) {
    self.ownership = ownership
    self.previous = previous
    self.file = file
    self.created = created
    self.failure = failure
    self.detail = detail
  }

  public var succeeded: Bool { failure == nil }
}
