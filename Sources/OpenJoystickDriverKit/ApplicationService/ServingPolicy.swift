/// Why OJD serves a controller no output.
public enum OutputDisabledReason: String, Codable, CaseIterable, Equatable, Sendable {
  /// The user turned virtual output off.
  case userDisabled
  /// Another virtual device already stands for the controller, so a second one would duplicate it.
  case upstreamVirtualDevice
  /// No persona can represent the controller's primary controls.
  case noVirtualProfile
}

/// The one way OJD serves a controller. Exactly one route holds for each controller.
public enum ServingRoute: Equatable, Sendable {
  /// The system serves the controller and OJD publishes nothing. The allowance is what OJD may
  /// still drive on the physical controller: the motors and lighting the system leaves undone.
  case nativePassThrough(PhysicalControllerOutputCapabilities)
  /// OJD publishes a virtual HID gamepad with this persona.
  case virtualHid(VirtualHIDProfileID)
  /// OJD's signed USB extension claims the controller and serves it.
  case extensionOwned
  /// OJD serves no output for the controller.
  case outputDisabled(OutputDisabledReason)
}

/// Everything the serving policy reads about one controller.
public struct ServingInput: Equatable, Sendable {
  /// How the physical input path is owned or observed.
  public var observation: ControllerOwnershipObservation
  /// Who the controller's record says serves the model.
  public var server: ControllerServer
  /// Whether virtual output is on.
  public var outputEnabled: Bool
  /// The normalized controls the controller declares.
  public var controls: Set<ControlID>
  /// The persona the user chose for this controller, if any.
  public var override: VirtualHIDProfileID?
  /// What OJD may drive on the physical controller when the system serves it.
  public var allowance: PhysicalControllerOutputCapabilities

  public init(
    observation: ControllerOwnershipObservation,
    server: ControllerServer = .system,
    outputEnabled: Bool = true,
    controls: Set<ControlID> = [],
    override: VirtualHIDProfileID? = nil,
    allowance: PhysicalControllerOutputCapabilities = .none
  ) {
    self.observation = observation
    self.server = server
    self.outputEnabled = outputEnabled
    self.controls = controls
    self.override = override
    self.allowance = allowance
  }

  /// The inputs one controller description carries.
  public init(
    _ device: ApplicationServiceDeviceDescription,
    outputEnabled: Bool = true,
    override: VirtualHIDProfileID? = nil
  ) {
    self.init(
      observation: device.physicalOwnership,
      server: device.recordServer,
      outputEnabled: outputEnabled,
      controls: device.capabilities.controls,
      override: override,
      allowance: device.physicalOutputCapabilities
    )
  }
}

/// The single pure decision of how OJD serves a controller. The service, the CLI, the GUI and the
/// endpoint ask it and decide nothing themselves.
public enum ServingPolicy {
  /// The route for `input`. Equal inputs give equal routes.
  public static func route(_ input: ServingInput) -> ServingRoute {
    if !input.outputEnabled { return .outputDisabled(.userDisabled) }
    if input.observation == .upstreamVirtualDevice {
      return .outputDisabled(.upstreamVirtualDevice)
    }
    // A record that gives a natively served model to OJD turns passthrough into a virtual gamepad.
    if input.observation.isServedBySystem && input.server == .system {
      return .nativePassThrough(input.allowance)
    }
    guard
      let selection = try? VirtualHIDProfileSelector.select(
        controls: input.controls,
        override: input.override
      )
    else { return .outputDisabled(.noVirtualProfile) }
    if input.observation == .driverKitOwnedUSB { return .extensionOwned }
    return .virtualHid(selection.profileID)
  }

  /// The route for one controller description.
  public static func route(
    for device: ApplicationServiceDeviceDescription,
    outputEnabled: Bool = true,
    override: VirtualHIDProfileID? = nil
  ) -> ServingRoute {
    route(ServingInput(device, outputEnabled: outputEnabled, override: override))
  }

  /// Whether the user can choose between the system and OJD serving a controller: the system serves
  /// it natively, or its record already gives it to OJD, and its family does not use raw USB,
  /// which always belongs to OJD.
  public static func offersServerChoice(
    observation: ControllerOwnershipObservation,
    server: ControllerServer,
    usesRawUSB: Bool
  ) -> Bool {
    !usesRawUSB && (observation == .nativeGamepad || server == .ojd)
  }
}

extension ServingRoute {
  /// Whether a virtual device may publish for the controller under this route.
  public var publishesVirtualDevice: Bool {
    switch self {
    case .virtualHid, .extensionOwned: true
    case .nativePassThrough, .outputDisabled: false
    }
  }
}
