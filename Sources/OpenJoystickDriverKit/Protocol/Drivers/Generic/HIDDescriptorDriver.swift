import Foundation

/// Descriptor-driven driver for the `hid.descriptor` protocol: HID controllers whose
/// report descriptor satisfies ``HIDDescriptorContract``.
///
/// Raw report layouts vary between devices, so IOKit decodes descriptor elements and this driver
/// folds them through a ``HIDUsageMap``: the record's, else the one the `hid.descriptor`
/// description selects for the report descriptor's shape, else the description's standard map.
public final class HIDDescriptorDriver: PhysicalProtocolDriver {
  private let model: ControllerModelID
  private var state = ControllerState.neutral
  /// Stick axes as decoded. HID Generic Desktop Y and Ry (and a Z/Rz layout's right-stick Rz) put
  /// the logical minimum up, so the decoded value is already Y down. An element carries one axis,
  /// so each keeps its pair's other.
  private var leftX: Float = 0
  private var leftY: Float = 0
  private var rightX: Float = 0
  private var rightY: Float = 0
  let usageMap: HIDUsageMap
  /// Whether the descriptor declares a usage the map binds to Share, which Xbox Series pads send
  /// as Consumer Record over Bluetooth.
  private let hasShareButton: Bool

  /// Creates a driver whose usage map the `hid.descriptor` description selects.
  public convenience init(model: ControllerModelID, reportDescriptor: Data? = nil) {
    self.init(model: model, reportDescriptor: reportDescriptor, usageMap: nil)
  }

  /// Creates a new HIDDescriptorDriver for a controller of `model`.
  ///
  /// `reportDescriptor` is the bound interface's HID report descriptor, when observed.
  /// `usageMap` is the record's map, if it declares one. Without one, the description's first
  /// shape that the descriptor's usages match selects the map, so a descriptor with Z and Rz, a
  /// Brake or Accelerator, and no Rx or Ry gets the Z/Rz layout (xpadneo
  /// `docs/descriptors/xb1s_linux.md`, `xbxs.md`, and `incompat/gamesir_g7_se.md`). Otherwise the
  /// description's standard map applies.
  init(
    model: ControllerModelID,
    reportDescriptor: Data? = nil,
    usageMap: HIDUsageMap?
  ) {
    self.model = model
    let fields =
      reportDescriptor.flatMap { HIDReportDescriptorParser.parse(descriptor: Array($0))?.fields }
      ?? []
    let usages = Set(fields.map { HIDUsage(usagePage: $0.usagePage, usage: $0.usage) })
    let description = ProtocolDescription.bundled[.hidDescriptor]
    guard
      let resolved = usageMap
        ?? description?.hidUsageShapes.first(where: { $0.matches(usages) })?.map
        ?? description?.hidUsageMap
    else { preconditionFailure("Resources/Protocols/hid.descriptor.json declares no usage map") }
    self.usageMap = resolved
    hasShareButton = usages.contains { (hidUsage: HIDUsage) in
      resolved.binding(page: UInt32(hidUsage.usagePage), usage: UInt32(hidUsage.usage))
        == .button(.share)
    }
    print("[HIDDescriptorDriver] Unrecognized controller \(model), using HID descriptors")
  }

  /// A new transport session starts from neutral input.
  public func resetProtocolState() {
    state = .neutral
    (leftX, leftY, rightX, rightY) = (0, 0, 0, 0)
  }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan(parsesHIDElementValues: true) }
  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    guard usageMap.controls.contains(.leftTriggerButton) else {
      return ControllerCapabilities(
        controls: ControlID.xboxLayout.union(hasShareButton ? [.guide, .share] : [.guide])
      )
    }
    return ControllerCapabilities(
      controls: ControlID.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTriggerButton, .rightTriggerButton,
      ])
    )
  }

  /// Raw reports are handled through IOKit's descriptor-decoded element callback.
  public func parse(report _: Data, receivedAt _: MonotonicTimestamp) throws -> ControllerEvent? {
    nil
  }

  /// Folds one HID usage into the state through the usage map, preserving paired stick
  /// coordinates. A usage the map does not name, or one from another report than the map's, is
  /// ignored.
  public func parse(
    elementValue value: HIDElementValue,
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard usageMap.reportID == nil || usageMap.reportID == value.reportID,
      let binding = usageMap.binding(page: value.usagePage, usage: value.usage)
    else { return nil }
    var next = state
    switch binding {
    case .button(let control): next.set(control, pressed: value.integerValue != 0)
    case .hat(let hat): next.hat = hat.direction(of: value)
    case .axis(let axis):
      let position = axis.value(of: value)
      switch axis.control {
      case .leftStickX: leftX = position
      case .leftStickY: leftY = position
      case .rightStickX: rightX = position
      case .rightStickY: rightY = position
      case .leftTrigger: next.leftTrigger = UnipolarValue(normalized: position)
      default: next.rightTrigger = UnipolarValue(normalized: position)
      }
      if !axis.isTrigger {
        next.leftStick = StickPosition(x: leftX, yDown: leftY)
        next.rightStick = StickPosition(x: rightX, yDown: rightY)
      }
    }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }
}
