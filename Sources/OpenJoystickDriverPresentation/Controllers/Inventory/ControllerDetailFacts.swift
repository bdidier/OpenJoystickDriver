import Foundation
import OpenJoystickDriverKit

/// One labelled fact of the Controllers detail.
struct ControllerFact: Equatable, Identifiable {
  enum Kind: Hashable {
    case publishedAs, serving, controllerProtocol, serialNumber
    case battery, chargingState, cableState
    case usbIdentifier, inputEndpoint, outputEndpoint
  }

  let kind: Kind
  let label: String
  let value: OJDValue

  var id: Kind { kind }
}

/// The facts the Controllers detail lists for one controller. A fact that applies but has no value
/// shows the hyphen; battery, charging and cable facts the controller does not report are left out.
enum ControllerDetailFacts {
  /// The facts shown directly in the detail.
  static func general(for device: ApplicationServiceDeviceDescription) -> [ControllerFact] {
    let always = [
      ControllerFact(
        kind: .publishedAs,
        label: OJDLocalized.string("controllers.publishedAs"),
        value: publishedAs(device)
      ),
      ControllerFact(
        kind: .serving,
        label: OJDLocalized.string("controllers.serving.label"),
        value: .text(device.servingRouteLabel)
      ),
      ControllerFact(
        kind: .controllerProtocol,
        label: OJDLocalized.string("common.protocol"),
        value: .text(device.protocolBinding.displayLabel)
      ),
      ControllerFact(
        kind: .serialNumber,
        label: OJDLocalized.string("common.serialNumber"),
        value: serialNumber(device)
      ),
    ]
    let power = [
      ControllerFact(
        kind: .battery,
        label: OJDLocalized.string("controllers.battery"),
        value: battery(device)
      ),
      ControllerFact(
        kind: .chargingState,
        label: OJDLocalized.string("controllers.chargingState"),
        value: chargingState(device)
      ),
      ControllerFact(
        kind: .cableState,
        label: OJDLocalized.string("controllers.cableState"),
        value: cableState(device)
      ),
    ].filter { $0.value != .none }
    return always + power
  }

  /// The identifiers and endpoints shown under Advanced.
  static func advanced(for device: ApplicationServiceDeviceDescription) -> [ControllerFact] {
    [
      ControllerFact(
        kind: .usbIdentifier,
        label: OJDLocalized.string("controllers.usbIdentifier"),
        value: usbIdentifier(device)
      ),
      ControllerFact(
        kind: .inputEndpoint,
        label: OJDLocalized.string("common.inputEndpoint"),
        value: .endpoint(device.inputEndpoint)
      ),
      ControllerFact(
        kind: .outputEndpoint,
        label: OJDLocalized.string("common.outputEndpoint"),
        value: .endpoint(device.outputEndpoint)
      ),
    ]
  }

  /// The virtual HID profile the controller publishes, or the one the service selected for it;
  /// the hyphen when there is none.
  static func publishedAs(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    let identity = device.presentedIdentity
    if identity.publishesVirtualDevice { return .text(identity.label) }
    if let selection = device.servingDecision.selection {
      return .text(selection.profileID.identity.publishedUSBIdentityLabel)
    }
    return .none
  }

  static func serialNumber(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    .reported(device.serialNumber)
  }

  static func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    .usbIdentifier(vendorID: device.vendorID, productID: device.productID)
  }

  static func battery(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    OJDValue(device.connectionState?.power.battery.percentageText)
  }

  static func chargingState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.charging ?? .unknown {
    case .discharging: return .text(OJDLocalized.string("controllers.discharging"))
    case .charging: return .text(OJDLocalized.string("controllers.charging"))
    case .full: return .text(OJDLocalized.string("controllers.batteryFull"))
    case .notChargeable: return .text(OJDLocalized.string("controllers.notChargeable"))
    case .unknown: return .none
    }
  }

  static func cableState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.wiredPower {
    case true?: return .text(OJDLocalized.string("settings.controllerConnectedShort"))
    case false?: return .text(OJDLocalized.string("settings.controllerDisconnectedShort"))
    case nil: return .none
    }
  }
}
