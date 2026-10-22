import OpenJoystickDriverKit

extension PhysicalRumbleMotor {
  /// The localized name of the motor.
  var title: String {
    switch self {
    case .lowFrequency: return OJDLocalized.string("ui.inputTest.lowFrequency")
    case .highFrequency: return OJDLocalized.string("ui.inputTest.highFrequency")
    case .leftTrigger: return OJDLocalized.string("ui.inputTest.leftTrigger")
    case .rightTrigger: return OJDLocalized.string("ui.inputTest.rightTrigger")
    case .leftHaptic: return OJDLocalized.string("ui.inputTest.leftHaptic")
    case .rightHaptic: return OJDLocalized.string("ui.inputTest.rightHaptic")
    }
  }
}

extension PhysicalLightingFeature {
  /// The localized name of the lighting feature.
  var title: String {
    switch self {
    case .playerIndicator: return OJDLocalized.string("ui.inputTest.playerIndicator")
    case .programmableColor: return OJDLocalized.string("ui.inputTest.color")
    case .programmableBrightness: return OJDLocalized.string("ui.inputTest.brightness")
    }
  }
}

extension PhysicalAdaptiveTrigger {
  /// The localized name of the trigger.
  var title: String {
    switch self {
    case .left: return OJDLocalized.string("ui.inputTest.leftTrigger")
    case .right: return OJDLocalized.string("ui.inputTest.rightTrigger")
    }
  }
}
