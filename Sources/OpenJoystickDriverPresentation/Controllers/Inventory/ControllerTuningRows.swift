import Foundation
import OpenJoystickDriverKit

/// One effective tuning value of a controller and the layer it comes from.
struct ControllerTuningRow: Equatable, Identifiable {
  /// The key as the record file names it, such as `stickDeadzone`.
  let name: String
  let value: String
  /// The layer that sets the value, such as `user`.
  let layer: String

  var id: String { name }

  /// The value and its layer as the row shows them, such as `0.1 (user)`.
  var text: String { "\(value) (\(layer))" }
}

/// The Tuning section of the Controllers detail, from the same layered record as
/// `ojd config show --controller`.
enum ControllerTuningRows {
  /// The tuning keys a layer sets for `record`'s model, in record-file order. A key only the
  /// driver default covers has no value to show, so it is left out; with no key set the section
  /// says the driver defaults apply.
  static func rows(for record: ControllerRecord) -> [ControllerTuningRow] {
    record.tuningValues.compactMap { entry in
      guard let value = entry.value else { return nil }
      return ControllerTuningRow(
        name: entry.key.rawValue,
        value: value == value.rounded() ? String(Int(value)) : String(value),
        layer: CommandLineName.kebab(entry.layer.rawValue)
      )
    }
  }
}
