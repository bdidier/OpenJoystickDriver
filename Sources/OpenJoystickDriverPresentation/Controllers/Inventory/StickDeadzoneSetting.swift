import Foundation
import OpenJoystickDriverKit

/// The stick dead zone of a controller model as the detail's setting row shows and changes it. The
/// driver keeps no default dead zone, so a model with no layer that sets one has none. A change
/// writes the user's controller record, as `ojd config set stickDeadzone` does.
struct StickDeadzoneSetting: Equatable {
  /// The step of one press of the setting's stepper.
  static let step = 0.01
  /// The values the stepper writes: a record accepts a dead zone above 0 and below 1.
  static let range = 0.01...0.99

  /// The effective value; nil while no layer sets one.
  let value: Double?
  /// The layer that sets the value; `driver` while none does.
  let layer: ControllerRecordLayer

  init(record: ControllerRecord) {
    let entry = record.tuningValues.first { $0.key == .stickDeadzone }
    value = entry?.value
    layer = entry?.layer ?? .driver
  }

  /// The value as the row shows it, or the driver default's name while no layer sets one.
  var text: String {
    value.map { String($0) } ?? OJDLocalized.string("cli.config.show.unset")
  }

  /// Whether the user's record sets the value, so removing it changes the effective value.
  var canReset: Bool { value != nil && layer == .user }

  /// The value one step above the current one, at most `range.upperBound`.
  var increased: Double { Self.clamped(Self.rounded((value ?? 0) + Self.step)) }

  /// The value one step below the current one, at least `range.lowerBound`; nil while no layer sets
  /// a value, because there is nothing below the driver default.
  var decreased: Double? { value.map { Self.clamped(Self.rounded($0 - Self.step)) } }

  private static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }

  private static func clamped(_ value: Double) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
