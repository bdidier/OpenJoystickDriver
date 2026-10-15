@testable import OpenJoystickDriverKit

/// One controller situation with the answers every caller of the serving policy must give.
package struct ServingFixture: Sendable {
  package let name: String
  package let observation: ControllerOwnershipObservation
  package let server: ControllerServer
  package let source: DeviceDiscoverySource
  package let accessRoute: ControllerAccessRoute
  package let outputEnabled: Bool
  package let override: VirtualHIDProfileID?
  /// The route the policy must decide.
  package let route: ServingRoute
  /// Whether the user can choose who serves the controller.
  package let offersServerChoice: Bool

  package var input: ServingInput {
    ServingInput(
      observation: observation,
      server: server,
      accessRoute: accessRoute,
      outputEnabled: outputEnabled,
      controls: ControlID.xboxLayout,
      override: override
    )
  }

  /// The controller as the service describes it.
  package var device: ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: 0x3537,
      productID: 0x100B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: source,
      physicalOwnership: observation,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: server,
      recordAccessRoute: accessRoute,
      capabilities: ControllerCapabilities(controls: ControlID.xboxLayout),
      sessionToken: .fixture("serving-fixture")
    )
  }

  private init(
    _ name: String,
    _ observation: ControllerOwnershipObservation,
    _ server: ControllerServer,
    source: DeviceDiscoverySource = .hid,
    accessRoute: ControllerAccessRoute = .system,
    outputEnabled: Bool = true,
    override: VirtualHIDProfileID? = nil,
    route: ServingRoute,
    offersServerChoice: Bool
  ) {
    self.name = name
    self.observation = observation
    self.server = server
    self.source = source
    self.accessRoute = accessRoute
    self.outputEnabled = outputEnabled
    self.override = override
    self.route = route
    self.offersServerChoice = offersServerChoice
  }

  /// The fixture set the four callers are compared over.
  package static let all: [Self] = [
    Self(
      "native gamepad",
      .nativeGamepad,
      .system,
      route: .nativePassThrough(.none),
      offersServerChoice: true
    ),
    Self(
      "native HID",
      .nativeHIDVisible,
      .system,
      route: .nativePassThrough(.none),
      offersServerChoice: false
    ),
    Self(
      "native claimed by OJD",
      .nativeGamepad,
      .ojd,
      route: .virtualHid(.generic),
      offersServerChoice: true
    ),
    Self(
      "seized HID",
      .exclusiveHID,
      .system,
      route: .virtualHid(.generic),
      offersServerChoice: false
    ),
    Self(
      "seized HID with override",
      .exclusiveHID,
      .system,
      override: .sdlCompatible,
      route: .virtualHid(.sdlCompatible),
      offersServerChoice: false
    ),
    Self(
      "raw USB claimed by OJD",
      .exclusiveRawUSB,
      .ojd,
      source: .rawUSB,
      accessRoute: .rawAccess,
      route: .virtualHid(.generic),
      offersServerChoice: false
    ),
    Self(
      "extension owned",
      .driverKitOwnedUSB,
      .system,
      source: .rawUSB,
      accessRoute: .extensionOwned,
      route: .extensionOwned,
      offersServerChoice: false
    ),
    Self(
      "upstream virtual",
      .upstreamVirtualDevice,
      .system,
      route: .outputDisabled(.upstreamVirtualDevice),
      offersServerChoice: false
    ),
    Self(
      "output off",
      .exclusiveHID,
      .system,
      outputEnabled: false,
      route: .outputDisabled(.userDisabled),
      offersServerChoice: false
    ),
  ]
}
