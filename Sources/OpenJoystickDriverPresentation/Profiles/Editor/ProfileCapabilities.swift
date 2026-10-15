import OpenJoystickDriverKit

enum ProfileCapabilityResolver {
  static func resolve(
    profile: RemappingProfile,
    connectedDevices: [ApplicationServiceDeviceDescription],
    registry: ProtocolDriverRegistry
  ) -> ControllerProfileCapabilities? {
    let resolved = deviceCapabilities(
      profile: profile,
      connectedDevices: connectedDevices,
      registry: registry
    )
    // A Joy-Con pair profile is scoped to the left half but maps controls from both halves.
    guard profile.joyConPair != nil, let resolved else { return resolved }
    let halves = JoyConHalf.generationProductIDs(forLeft: profile.device.productID).compactMap {
      registry.profileCapabilities(
        for: ControllerModelID(vendorID: profile.device.vendorID, productID: $0)
      )
    }
    let pairInput = halves.map(\.physicalInput).reduce(resolved.physicalInput) { $0.union($1) }
    return ControllerProfileCapabilities(
      physicalInput: pairInput,
      physicalOutput: resolved.physicalOutput
    )
  }

  private static func deviceCapabilities(
    profile: RemappingProfile,
    connectedDevices: [ApplicationServiceDeviceDescription],
    registry: ProtocolDriverRegistry
  ) -> ControllerProfileCapabilities? {
    let matchingDevices = connectedDevices.filter {
      $0.vendorID == profile.device.vendorID && $0.productID == profile.device.productID
    }
    if let first = matchingDevices.first {
      return matchingDevices.dropFirst().reduce(capabilities(for: first)) {
        $0.intersecting(capabilities(for: $1))
      }
    }
    return registry.profileCapabilities(
      for: ControllerModelID(vendorID: profile.device.vendorID, productID: profile.device.productID)
    )
  }

  private static func capabilities(
    for device: ApplicationServiceDeviceDescription
  ) -> ControllerProfileCapabilities {
    ControllerProfileCapabilities(
      physicalInput: device.capabilities,
      physicalOutput: device.physicalOutputCapabilities
    )
  }
}

enum ProfileCapabilityPolicy {
  static func supports(
    _ source: RemappingSource,
    capabilities: ControllerProfileCapabilities?
  ) -> Bool {
    guard let input = capabilities?.physicalInput else { return true }
    switch source {
    case .dpad: return !input.controls.isDisjoint(with: Control.dpad)
    case .button(let button):
      return input.controls.contains(button)
    case .axis(let axis), .axisDirection(let axis, _):
      return input.controls.contains(axis.control)
    case .triggerStage(let trigger, _):
      return input.controls.contains(trigger == .left ? .leftTrigger : .rightTrigger)
    case .motionLean: return input.motion
    case .touchContact(let surface): return supports(surface, input: input)
    case .touchGrid(let source): return supports(source.surface, input: input)
    case .touchSwipe(let source): return supports(source.surface, input: input)
    }
  }

  static func supports(
    _ destination: RemappingDestination,
    capabilities: ControllerProfileCapabilities?
  ) -> Bool {
    guard capabilities != nil else { return true }
    guard case .physical(let output) = destination else { return true }
    guard let physical = capabilities?.physicalOutput else { return false }
    switch output {
    case .rumble(let motor, _): return physical.rumbleMotors.contains(motor)
    case .playerIndicator: return physical.lightingFeatures.contains(.playerIndicator)
    case .color: return physical.lightingFeatures.contains(.programmableColor)
    case .brightness: return physical.lightingFeatures.contains(.programmableBrightness)
    case .adaptiveTrigger(let trigger, _): return physical.adaptiveTriggers.contains(trigger)
    }
  }

  private static func supports(
    _ surface: RemappingTouchSurface,
    input: ControllerCapabilities
  ) -> Bool {
    let physicalSurface: ControllerTouchSurface
    switch surface {
    case .primary: physicalSurface = .primary
    case .left: physicalSurface = .left
    case .right: physicalSurface = .right
    }
    return input.touchSurfaces.contains(physicalSurface)
  }
}
