import Foundation

/// Selects the motion source for an explicitly paired left/right Joy-Con session.
public enum RemappingJoyConGyroSelection: String, Codable, CaseIterable, Sendable {
  case disabled = "Disabled"
  case left = "Left"
  case right = "Right"
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

/// The side of a Joy-Con half that a paired session accepts, from the `JoyConLeft` and
/// `JoyConRight` layouts of the current controller records.
public enum JoyConHalf: Equatable, Sendable {
  case left
  case right

  public init?(vendorID: UInt16, productID: UInt16) {
    let layout =
      DeviceCatalog.current.withLock { $0 }
      .record(for: ControllerModelID(vendorID: vendorID, productID: productID))?.parameters.layout
    switch layout {
    case .joyConLeft: self = .left
    case .joyConRight: self = .right
    default: return nil
    }
  }

  /// A left-half product ID followed by the right halves of its generation: the records of the
  /// same vendor and the same Switch 2 membership. Empty when no record declares a left half.
  public static func generationProductIDs(forLeft productID: UInt16) -> [UInt16] {
    let catalog = DeviceCatalog.current.withLock { $0 }
    let halves = catalog.hidModels.compactMap { model in
      catalog.record(for: model).map {
        (model: model, protocolID: $0.physicalProtocolID, layout: $0.parameters.layout)
      }
    }
    let lefts = halves.filter {
      $0.model.productID == productID && $0.layout == .joyConLeft
    }
    guard !lefts.isEmpty else { return [] }
    let rights = halves.filter { right in
      right.layout == .joyConRight
        && lefts.contains {
          $0.model.vendorID == right.model.vendorID
            && $0.protocolID == right.protocolID
        }
    }
    return [productID] + rights.map(\.model.productID)
  }
}
