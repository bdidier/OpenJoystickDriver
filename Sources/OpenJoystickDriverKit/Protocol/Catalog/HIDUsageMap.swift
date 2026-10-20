import Foundation

/// What a HID usage drives: the typed form of a record's `input.hidUsageMap`.
///
/// A map names each usage it reads by page and usage ID and binds it to a canonical control as a
/// button, an axis or a hat switch. ``HIDDescriptorDriver`` folds IOKit's decoded element values
/// through it; a usage the map does not name is ignored.
struct HIDUsageMap: Equatable, Sendable {
  /// A usage bound to a button, an axis or a hat switch.
  enum Binding: Equatable, Sendable {
    /// Pressed while the element value is nonzero.
    case button(Control)
    case axis(Axis)
    case hat(Hat)
  }

  /// A stick or trigger axis.
  struct Axis: Equatable, Sendable {
    /// One of the four stick axes or a trigger.
    let control: Control
    /// Reverses the axis: a stick is negated, a trigger reads one minus its value.
    let isInverted: Bool
    /// The raw range that scales to the full axis; nil takes the element's logical range.
    let range: ClosedRange<Int>?
    /// A stick reads 0 while its magnitude is within this fraction of full deflection, and a
    /// trigger while it is within this fraction of full pull; the rest rescales to the full range.
    let deadZone: Float?

    var isTrigger: Bool { control == .leftTrigger || control == .rightTrigger }

    /// The element value on this axis: a stick in -1...1 and a trigger in 0...1. A span of zero
    /// reads 0.
    func value(of element: HIDElementValue) -> Float {
      let low = range?.lowerBound ?? element.logicalMinimum
      let high = range?.upperBound ?? element.logicalMaximum
      guard high > low else { return 0 }
      let unit = Float(element.integerValue - low) / Float(high - low)
      if isTrigger {
        let pull = min(1, max(0, unit))
        return Self.applying(deadZone, to: isInverted ? 1 - pull : pull)
      }
      let deflection = min(1, max(-1, unit * 2 - 1))
      return Self.applying(deadZone, to: isInverted ? -deflection : deflection)
    }

    private static func applying(_ deadZone: Float?, to value: Float) -> Float {
      guard let deadZone else { return value }
      let magnitude = abs(value)
      guard magnitude > deadZone else { return 0 }
      let rescaled = (magnitude - deadZone) / (1 - deadZone)
      return value < 0 ? -rescaled : rescaled
    }
  }

  /// A hat switch: eight directions from north, clockwise, then a null state.
  struct Hat: Equatable, Sendable {
    /// The eight direction values plus the range's first as north: `0...7` or `1...8`. Nil takes
    /// the element's logical minimum as north.
    let range: ClosedRange<Int>?

    func direction(of element: HIDElementValue) -> HatDirection {
      let position = element.integerValue - (range?.lowerBound ?? element.logicalMinimum)
      let directions: [HatDirection] = [
        .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
      ]
      guard position >= 0, position < directions.count else { return .neutral }
      return directions[position]
    }
  }

  struct Entry: Equatable, Sendable {
    let usage: HIDUsage
    let binding: Binding
  }

  /// The only report the map reads, by report ID; nil reads every report.
  let reportID: UInt32?
  let entries: [Entry]
  private let bindings: [HIDUsage: Binding]

  /// Throws a ``ControllerRecordProblem`` for a usage named twice, a button on an axis or hat
  /// control, an axis on any other control, an empty or reversed range, or a dead zone outside
  /// the open interval from 0 to 1.
  init(reportID: UInt32? = nil, entries: [Entry]) throws {
    guard !entries.isEmpty else { throw ControllerRecordProblem("a usage map must not be empty") }
    var bindings: [HIDUsage: Binding] = [:]
    for entry in entries {
      let name = "usage \(entry.usage.usagePage)/\(entry.usage.usage)"
      guard bindings.updateValue(entry.binding, forKey: entry.usage) == nil else {
        throw ControllerRecordProblem("\(name) is named twice")
      }
      switch entry.binding {
      case .button(let control):
        guard !Control.stickAxes.contains(control), !Control.dpad.contains(control) else {
          throw ControllerRecordProblem("\(name) is a button; \(control.rawValue) is not")
        }
      case .axis(let axis):
        guard Control.stickAxes.contains(axis.control) || axis.isTrigger else {
          throw ControllerRecordProblem("\(name) is an axis; \(axis.control.rawValue) is not")
        }
        if let range = axis.range, range.isEmpty || range.lowerBound == range.upperBound {
          throw ControllerRecordProblem("\(name) range must have min below max")
        }
        if let deadZone = axis.deadZone, !(deadZone > 0 && deadZone < 1) {
          throw ControllerRecordProblem("\(name) deadZone must be above 0 and below 1")
        }
      case .hat(let hat):
        if let range = hat.range, range != 0...7, range != 1...8 {
          throw ControllerRecordProblem("\(name) hat range must be 0...7 or 1...8")
        }
      }
    }
    self.reportID = reportID
    self.entries = entries
    self.bindings = bindings
  }

  func binding(page: UInt32, usage: UInt32) -> Binding? {
    bindings[HIDUsage(usagePage: Int(page), usage: Int(usage))]
  }

  /// The triggers the map reads as buttons: a physical digital trigger signal.
  var digitalTriggers: Set<Control> {
    Set(
      entries.compactMap { entry in
        guard case .button(let control) = entry.binding else { return nil }
        return control == .leftTrigger || control == .rightTrigger ? control : nil
      }
    )
  }

  /// The controls the map can drive.
  var controls: Set<Control> {
    var controls: Set<Control> = []
    for entry in entries {
      switch entry.binding {
      case .button(let control): controls.insert(control)
      case .axis(let axis): controls.insert(axis.control)
      case .hat: controls.formUnion(Control.dpad)
      }
    }
    return controls
  }
}

/// A descriptor shape and the usage map it selects: the `HIDDescriptor` description's way to
/// recognise a family of pads from their report descriptor alone.
struct HIDUsageShape: Equatable, Sendable {
  /// Usages the descriptor must declare.
  let present: Set<HIDUsage>
  /// Usages the descriptor must not declare.
  let absent: Set<HIDUsage>
  /// When nonempty, at least one of these usages the descriptor must declare.
  let anyOf: Set<HIDUsage>
  let map: HIDUsageMap

  func matches(_ usages: Set<HIDUsage>) -> Bool {
    usages.isSuperset(of: present) && usages.isDisjoint(with: absent)
      && (anyOf.isEmpty || !usages.isDisjoint(with: anyOf))
  }
}
