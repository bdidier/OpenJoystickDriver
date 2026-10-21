@testable import OpenJoystickDriverKit

extension ControllerSessionToken {
  /// The token `E-` and `label` padded with `0` to 16 characters, so tests can name one.
  package static func fixture(_ label: String) -> ControllerSessionToken {
    let body = label + String(repeating: "0", count: max(0, 16 - label.count))
    guard let token = ControllerSessionToken(rawValue: prefix + body) else {
      preconditionFailure("A token label is at most 16 base64url characters.")
    }
    return token
  }
}

/// The session token text of the fixture controller `label`, as the runtime reports it.
package func token(_ label: String) -> String { ControllerSessionToken.fixture(label).rawValue }

extension ControllerPortKey {
  /// The port key `U-` and `label` padded with `0` to 16 characters, so tests can name one.
  package static func fixture(_ label: String) -> ControllerPortKey {
    let body = label + String(repeating: "0", count: max(0, 16 - label.count))
    guard let portKey = ControllerPortKey(rawValue: prefix + body) else {
      preconditionFailure("A port key label is at most 16 base64url characters.")
    }
    return portKey
  }
}

extension ApplicationServiceDeviceDescription {
  /// A USB `HIDDescriptor` controller whose session token is `.fixture(id)`, for tests that
  /// list controllers.
  package static func fixture(
    id: String,
    name: String = "Test Pad",
    vendorID: UInt16 = 0x045E,
    productID: UInt16 = 0x028E,
    outputs: PhysicalControllerOutputCapabilities = .none,
    unit: String? = nil,
    power: ControllerConnectionState.Power? = nil,
    inputHealth: ControllerInputHealth = ControllerInputHealth(state: .healthy),
    physicalOutputOwner: ControllerServer = .ojd,
    tuning: ControllerTuning = .none
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: vendorID,
      productID: productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: outputs,
      physicalOutputOwner: physicalOutputOwner,
      tuning: tuning,
      connectionState: power.map {
        ControllerConnectionState(transport: .usb, backend: .hid, isConnected: true, power: $0)
      },
      inputHealth: inputHealth,
      sessionToken: .fixture(id),
      portKey: unit.map(ControllerPortKey.fixture)
    )
  }
}
