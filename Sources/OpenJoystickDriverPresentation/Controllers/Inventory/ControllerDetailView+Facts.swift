#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    var body: some View {
      Form {
        Section { controllerHeader }
        Section {
          controllerSessionAction
          if device.supportsWirelessDisconnect { wirelessDisconnectAction }
          if let failure = viewModel.controllerActionFailures[device.sessionToken.rawValue] {
            controllerActionFailure(failure)
          }
        }
        Section { activeProfileRow }
        Section {
          ForEach(controllerFacts, id: \.label) { fact in
            if fact.isSerialNumber {
              SerialNumberRow(
                label: fact.label,
                serial: fact.value,
                visibility: $serialVisibility
              )
            } else {
              OJDLabeledValue(fact.label, fact.value)
            }
          }
        }
        Section { inputTestAction }
        if ControllerServerPicker.isShown(for: device) {
          Section { ControllerServerPicker(viewModel: viewModel, device: device) }
        }
        if device.physicalOwnership != .systemGamepad {
          // A per-controller identity collapses Advanced again on a new selection.
          Section {
            VirtualHIDProfileOverrideView(viewModel: viewModel, device: device).id(
              device.sessionToken.rawValue
            )
          }
        }
      }.ojdGroupedForm().ojdAccessibilityLabel(device.name).ojdAccessibilityValue(
        accessibilityValue
      ).alert(
        isPresented: $confirmsWirelessDisconnect
      ) {
        Alert(
          title: Text(
            OJDLocalized.string(
              "controllers.disconnectWirelessConfirmTitle"
            )
          ),
          message: Text(
            OJDLocalized.formatted(
              "controllers.disconnectWirelessConfirmMessage",
              device.name
            )
          ),
          primaryButton: .destructive(
            Text(
              OJDLocalized.string("controllers.disconnectWirelessConfirm")
            )
          ) { Task { @MainActor in await viewModel.disconnectWirelessController(device) } },
          secondaryButton: .cancel()
        )
      }
    }

    private var wirelessDisconnectAction: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            OJDLocalized.string(
              "controllers.disconnectWireless"
            )
          ).font(.headline)
          Text(
            OJDLocalized.string(
              "controllers.disconnectWirelessSummary"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 12)
        Button(
          OJDLocalized.string("controllers.disconnectWirelessButton")
        ) { confirmsWirelessDisconnect = true }
      }
    }

    private func controllerActionFailure(_ message: String) -> some View {
      HStack(alignment: .top, spacing: 8) {
        OJDSystemSymbol(
          name: SemanticState.failure.presentation.symbolName,
          fallback: OJDLocalized.string("common.needsAttention")
        ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }.ojdAccessibilityLabel(
        OJDLocalized.string("common.needsAttention")
      ).ojdAccessibilityValue(message)
    }

    private var inputTestAction: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(OJDLocalized.string("inputTest.title")).font(.headline)
          Text(
            OJDLocalized.string(
              "inputTest.summary"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        Spacer(minLength: 12)
        Button(OJDLocalized.string("inputTest.open")) {
          openInputTest(device)
        }.disabled(device.sessionState == .suspended)
      }
    }

    private var controllerSessionAction: some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            device.sessionState == .suspended
              ? OJDLocalized.string("controllers.suspended")
              : OJDLocalized.string(
                "controllers.sessionActive"
              )
          ).font(.headline)
          Text(
            device.sessionState == .suspended
              ? OJDLocalized.string(
                "controllers.suspendedSummary"
              )
              : OJDLocalized.string(
                "controllers.disconnectSummary"
              )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 12)
        if device.sessionState == .suspended {
          Button(OJDLocalized.string("controllers.resume")) {
            Task { @MainActor in await viewModel.resumeController(device) }
          }
        } else {
          Button(
            OJDLocalized.string(
              "controllers.disconnectFromOJD"
            )
          ) { Task { @MainActor in await viewModel.suspendController(device) } }
        }
      }
    }

    private var controllerHeader: some View {
      HStack(alignment: .center, spacing: 10) {
        let presentation = device.publishedIdentityPresentation
        OJDSystemSymbol(
          name: presentation.controllerSymbolName,
          fallback: nil,
          fallbackSymbolName: presentation.controllerSymbolFallback
        ).font(.title).foregroundColor(presentation.glyphFamily.controllerSymbolColor)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(device.name).font(.headline.weight(.semibold)).lineLimit(1)
          Text(headerSubtitle)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 0)
      }
    }

    @ViewBuilder
    private var activeProfileRow: some View {
      switch activeProfile {
      case .loading:
        OJDLabeledValue(
          OJDLocalized.string("controllers.activeProfile"),
          OJDLocalized.string("status.checking")
        )
      case .noProfile:
        OJDLabeledValue(OJDLocalized.string("controllers.activeProfile"), OJDValue.none)
      case .profile(let name):
        OJDLabeledValue(OJDLocalized.string("controllers.activeProfile"), name)
      case .unavailable(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "controllers.profileUnavailable"
          ),
          message: message
        )
      case .error(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "controllers.profileLoadError"
          ),
          message: message
        )
      }
    }

    private func profileFailureRow(label: String, message: String) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(OJDLocalized.string("controllers.activeProfile"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          Spacer()
          Text(OJDLocalized.string("common.needsAttention"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }

        Text(label).font(.caption.weight(.semibold))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        Button(OJDLocalized.string("common.tryAgain"), action: retry)

      }
    }

    private var controllerFacts: [(label: String, value: OJDValue, isSerialNumber: Bool)] {
      [
        (
          OJDLocalized.string("controllers.publishedAs"), .text(device.publishedIdentityLabel),
          false
        ),
        (OJDLocalized.string("controllers.serving.label"), .text(device.servingRouteLabel), false),
        (OJDLocalized.string("common.protocol"), .text(device.protocolBinding.displayLabel), false),
        (OJDLocalized.string("common.serialNumber"), serialNumberValue, true),
        (OJDLocalized.string("controllers.battery"), batteryValue, false),
        (OJDLocalized.string("controllers.chargingState"), chargingStateValue, false),
        (OJDLocalized.string("controllers.cableState"), cableStateValue, false),
        (OJDLocalized.string("controllers.usbIdentifier"), usbIdentifierValue, false),
        (
          OJDLocalized.string("common.inputEndpoint"), OJDValue.endpoint(device.inputEndpoint),
          false
        ),
        (
          OJDLocalized.string("common.outputEndpoint"), OJDValue.endpoint(device.outputEndpoint),
          false
        ),
      ]
    }

    /// The connection, when the controller reports one, then the published identity.
    private var headerSubtitle: String {
      [connectionValue.textOrNil, device.publishedIdentityLabel].compactMap { $0 }.joined(
        separator: " · "
      )
    }

    var connectionValue: OJDValue { .reported(device.connection) }

    var serialNumberValue: OJDValue { .reported(device.serialNumber) }

    var usbIdentifierValue: OJDValue {
      .usbIdentifier(vendorID: device.vendorID, productID: device.productID)
    }

    var batteryValue: OJDValue { OJDValue(device.connectionState?.power.battery.percentageText) }

    var chargingStateValue: OJDValue {
      switch device.connectionState?.power.charging ?? .unknown {
      case .discharging: return .text(OJDLocalized.string("controllers.discharging"))
      case .charging: return .text(OJDLocalized.string("controllers.charging"))
      case .full: return .text(OJDLocalized.string("controllers.batteryFull"))
      case .notChargeable: return .text(OJDLocalized.string("controllers.notChargeable"))
      case .unknown: return .none
      }
    }

    var cableStateValue: OJDValue {
      switch device.connectionState?.power.wiredPower {
      case true?: return .text(OJDLocalized.string("settings.controllerConnectedShort"))
      case false?: return .text(OJDLocalized.string("settings.controllerDisconnectedShort"))
      case nil: return .none
      }
    }
  }

#endif
