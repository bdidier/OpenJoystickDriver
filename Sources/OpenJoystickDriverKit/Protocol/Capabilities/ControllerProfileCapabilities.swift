/// Controller features that can be selected safely while editing a remapping profile.
public struct ControllerProfileCapabilities: Equatable, Sendable {
  public let physicalInput: ControllerCapabilities
  public let physicalOutput: PhysicalControllerOutputCapabilities

  /// A device OJD cannot describe: every control stays selectable, without
  /// touch, motion or physical output.
  public static let unknown = Self(
    physicalInput: ControllerCapabilities(controls: Set(Control.allCases)),
    physicalOutput: .none
  )

  public init(
    physicalInput: ControllerCapabilities,
    physicalOutput: PhysicalControllerOutputCapabilities
  ) {
    self.physicalInput = physicalInput
    self.physicalOutput = physicalOutput
  }

  public var supportsStickAxes: Bool {
    !physicalInput.controls.isDisjoint(with: [.leftStickX, .leftStickY, .rightStickX, .rightStickY])
  }

  public var supportsAnalogTriggers: Bool {
    !physicalInput.controls.isDisjoint(with: [.leftTrigger, .rightTrigger])
  }

  public func intersecting(_ other: Self) -> Self {
    Self(
      physicalInput: physicalInput.intersecting(other.physicalInput),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: intersection(physicalOutput.rumbleMotors, other.physicalOutput.rumbleMotors),
        lightingFeatures: intersection(
          physicalOutput.lightingFeatures,
          other.physicalOutput.lightingFeatures
        ),
        binaryRumbleMotors: intersection(
          physicalOutput.binaryRumbleMotors,
          other.physicalOutput.binaryRumbleMotors
        ),
        adaptiveTriggers: intersection(
          physicalOutput.adaptiveTriggers,
          other.physicalOutput.adaptiveTriggers
        )
      )
    )
  }
}

private func intersection<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> [Element] {
  lhs.filter(rhs.contains)
}
