#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperControllerSummaryView: View {
    @ObservedObject
    var model: DeveloperToolsViewModel
    var body: some View {
      Section(OJDLocalized.string("developer.controllerDetails")) {
        Picker(
          OJDLocalized.string("developer.controller"),
          selection: Binding(
            get: { model.selectedDevice?.sessionToken.rawValue ?? "" },
            set: { model.selectDevice(sessionToken: $0) }
          )
        ) {
          ForEach(model.devices, id: \.sessionToken) { device in
            Text(device.name).tag(device.sessionToken.rawValue)
          }
        }
        if let device = model.selectedDevice { controllerFacts(device) }
        Button(OJDLocalized.string("common.refresh"), action: model.requestRefresh)
          .disabled(model.isCapturing)
      }
    }

    @ViewBuilder
    private func controllerFacts(_ device: ApplicationServiceDeviceDescription) -> some View {
      OJDLabeledValue(
        OJDLocalized.string("developer.usbID"),
        OJDValue.usbIdentifier(vendorID: device.vendorID, productID: device.productID)
      )
      OJDLabeledValue(
        OJDLocalized.string("common.protocol"),
        "\(device.protocolBinding.protocolID.displayName) "
          + "(\(device.protocolBinding.commandLineName))"
      )
      DeveloperSerialRow(serial: OJDValue.reported(device.serialNumber)).id(
        device.sessionToken.rawValue
      )
      OJDLabeledValue(OJDLocalized.string("developer.route"), routeName(device.discoverySource))
      OJDLabeledValue(OJDLocalized.string("developer.connection"), device.connection)
      OJDLabeledValue(
        OJDLocalized.string("developer.usbEndpoints"),
        String(
          format: "%@ 0x%02X · %@ 0x%02X",
          OJDLocalized.string("common.inputEndpoint"),
          device.inputEndpoint,
          OJDLocalized.string("common.outputEndpoint"),
          device.outputEndpoint
        )
      )
      OJDLabeledValue(
        OJDLocalized.string("developer.buttons"),
        buttonValue(model.latestInput?.pressed)
      )
      OJDLabeledValue(
        OJDLocalized.string("developer.leftStick"),
        stickValue(model.latestInput?.leftStick)
      )
      OJDLabeledValue(
        OJDLocalized.string("developer.rightStick"),
        stickValue(model.latestInput?.rightStick)
      )
    }

    /// Raw canonical values; Y points down.
    private func stickValue(_ stick: StickPosition?) -> String {
      let stick = stick ?? .center
      return "\(stick.x.rawValue), \(stick.y.rawValue)"
    }

    private func buttonValue(_ pressed: Set<Control>?) -> String {
      guard let pressed, !pressed.isEmpty else {
        return OJDLocalized.string("common.none")
      }
      return Control.allCases.filter(pressed.contains).map(\.rawValue).joined(separator: ", ")
    }

    private func routeName(_ value: DeviceDiscoverySource) -> String {
      switch value {
      case .hid: return OJDLocalized.string("developer.hid")
      case .rawUSB: return OJDLocalized.string("developer.rawUSB")
      }
    }
  }

  /// The serial number row; it is blurred until revealed, and starts blurred for each controller.
  private struct DeveloperSerialRow: View {
    let serial: OJDValue
    @State
    private var visibility = SerialNumberVisibility()

    var body: some View {
      SerialNumberRow(
        label: OJDLocalized.string("common.serialNumber"),
        serial: serial,
        visibility: $visibility
      )
    }
  }

#endif
