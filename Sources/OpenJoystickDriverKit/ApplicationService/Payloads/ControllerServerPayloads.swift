import Foundation

/// Arguments of `setControllerServer`: the controller model and who serves it, `system` or
/// `ojd`.
public struct LocalServiceRPCControllerServerArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let server: ControllerServer

  public init(vendorID: Int, productID: Int, server: ControllerServer) {
    self.vendorID = vendorID
    self.productID = productID
    self.server = server
  }
}

/// Why a `setControllerServer` request changed nothing. The user record stays as it was.
public enum ControllerServerFailure: String, Codable, Equatable, Sendable {
  /// The model's family uses raw USB, so OJD always serves it.
  case rawUSB
  /// macOS does not serve the model natively, so OJD always serves it.
  case notNative
  /// Neither the user directory, the bundled catalog, nor an installed package has a record of
  /// the model, so there is nothing to patch.
  case noRecord
  /// The vendor or product ID of the request is outside `0...0xFFFF`.
  case invalidRequest
  /// The existing user record, or the record with the requested `server`, is invalid.
  case invalidRecord
  /// The user record cannot be written.
  case persistenceFailed
}

/// Result of `setControllerServer`.
public struct ControllerServerResult: Codable, Equatable, Sendable {
  /// The server the request asked for.
  public let server: ControllerServer
  /// The model's effective server before the request.
  public let previous: ControllerServer
  /// The user record the request writes; nil when it was refused before a file was chosen.
  public let file: String?
  /// Whether the request created the user record.
  public let created: Bool
  public let failure: ControllerServerFailure?
  /// The problem text of `invalidRecord` or `persistenceFailed`.
  public let detail: String?

  public init(
    server: ControllerServer,
    previous: ControllerServer,
    file: String?,
    created: Bool,
    failure: ControllerServerFailure?,
    detail: String? = nil
  ) {
    self.server = server
    self.previous = previous
    self.file = file
    self.created = created
    self.failure = failure
    self.detail = detail
  }

  public var succeeded: Bool { failure == nil }
}
