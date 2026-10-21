import Foundation

/// One tuning key with its effective value and the layer that set it. `value` is nil while only
/// the driver default applies, which the driver picks itself.
public struct ControllerTuningValue: Equatable, Sendable {
  public let key: ControllerTuning.Key
  public let value: Double?
  public let layer: ControllerRecordLayer

  public init(key: ControllerTuning.Key, value: Double?, layer: ControllerRecordLayer) {
    self.key = key
    self.value = value
    self.layer = layer
  }

  /// Every key with its value in `tuning` and its entry in `layers`, by the key's JSON name; a
  /// key no layer names is the driver's.
  static func values(
    of tuning: ControllerTuning,
    layers: [String: ControllerRecordLayer]
  ) -> [Self] {
    ControllerTuning.Key.allCases.map { key in
      Self(
        key: key,
        value: tuning.text(of: key).flatMap(Double.init),
        layer: layers[key.rawValue] ?? .driver
      )
    }
  }
}

extension ControllerRecord {
  /// Every tuning key with its effective value and the layer it comes from.
  public var tuningValues: [ControllerTuningValue] {
    ControllerTuningValue.values(of: tuning, layers: tuningLayers)
  }
}

extension ControllerRecordSet {
  /// Every tuning key with the value `all.patch.json` gives it, or the driver default.
  public var defaultTuningValues: [ControllerTuningValue] {
    let tuning = defaults?.tuning ?? .none
    let layers = Dictionary(
      uniqueKeysWithValues: tuning.setKeys.map { ($0.rawValue, ControllerRecordLayer.global) }
    )
    return ControllerTuningValue.values(of: tuning, layers: layers)
  }
}
