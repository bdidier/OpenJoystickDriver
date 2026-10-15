import Foundation

/// Selects the motion source for an explicitly paired left/right Joy-Con session.
public enum RemappingJoyConGyroSelection: String, Codable, CaseIterable, Sendable {
  case disabled
  case left
  case right
}

/// Profile behavior used only after two exact runtime Joy-Con identities are paired.
public struct RemappingJoyConPairSettings: Codable, Equatable, Sendable {
  public let gyroSelection: RemappingJoyConGyroSelection

  public init(gyroSelection: RemappingJoyConGyroSelection = .right) {
    self.gyroSelection = gyroSelection
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case gyroSelection }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    gyroSelection = try values.decode(RemappingJoyConGyroSelection.self, forKey: .gyroSelection)
  }
}

/// The side of a Joy-Con half that a paired session accepts, from the `joy-con-left` and
/// `joy-con-right` quirks of the current controller records.
public enum JoyConHalf: Equatable, Sendable {
  case left
  case right

  public init?(vendorID: UInt16, productID: UInt16) {
    let quirks =
      DeviceCatalog.current.withLock { $0 }
      .record(for: ControllerModelID(vendorID: vendorID, productID: productID))?.quirks ?? []
    if quirks.contains(.joyConLeft) {
      self = .left
    } else if quirks.contains(.joyConRight) {
      self = .right
    } else {
      return nil
    }
  }

  /// A left-half product ID followed by the right halves of its generation: the records of the
  /// same vendor and the same Switch 2 membership. Empty when no record declares a left half.
  public static func generationProductIDs(forLeft productID: UInt16) -> [UInt16] {
    let catalog = DeviceCatalog.current.withLock { $0 }
    let halves = catalog.hidModels.compactMap { model in
      catalog.record(for: model).map {
        (model: model, protocolID: $0.physicalProtocolID, quirks: $0.quirks)
      }
    }
    let lefts = halves.filter {
      $0.model.productID == productID && $0.quirks.contains(.joyConLeft)
    }
    guard !lefts.isEmpty else { return [] }
    let rights = halves.filter { right in
      right.quirks.contains(.joyConRight)
        && lefts.contains {
          $0.model.vendorID == right.model.vendorID
            && $0.protocolID == right.protocolID
        }
    }
    return [productID] + rights.map(\.model.productID)
  }
}
