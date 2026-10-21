import OpenJoystickDriverKit

extension PhysicalRumbleMotor {
  /// The localized name of the motor.
  var title: String {
    switch self {
    case .lowFrequency: return OJDLocalized.string("inputTest.lowFrequency")
    case .highFrequency: return OJDLocalized.string("inputTest.highFrequency")
    case .leftTrigger: return OJDLocalized.string("inputTest.leftTrigger")
    case .rightTrigger: return OJDLocalized.string("inputTest.rightTrigger")
    case .leftHaptic: return OJDLocalized.string("inputTest.leftHaptic")
    case .rightHaptic: return OJDLocalized.string("inputTest.rightHaptic")
    }
  }
}

extension PhysicalLightingFeature {
  /// The localized name of the lighting feature.
  var title: String {
    switch self {
    case .playerIndicator: return OJDLocalized.string("inputTest.playerIndicator")
    case .programmableColor: return OJDLocalized.string("inputTest.color")
    case .programmableBrightness: return OJDLocalized.string("inputTest.brightness")
    }
  }
}

extension PhysicalAdaptiveTrigger {
  /// The localized name of the trigger.
  var title: String {
    switch self {
    case .left: return OJDLocalized.string("inputTest.leftTrigger")
    case .right: return OJDLocalized.string("inputTest.rightTrigger")
    }
  }
}
