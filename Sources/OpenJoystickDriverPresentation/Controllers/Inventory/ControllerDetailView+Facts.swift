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
        Section {
          activeProfileRow
          ForEach(ControllerDetailFacts.general(for: device)) { fact in
            if fact.kind == .serialNumber {
              SerialNumberRow(label: fact.label, serial: fact.value, visibility: $serialVisibility)
            } else {
              OJDLabeledValue(fact.label, fact.value)
            }
          }
        }
        Section { inputTestAction }
        if ControllerServerPicker.isShown(for: device) {
          Section {
            ControllerServerPicker(viewModel: viewModel, device: device)
            if let record {
              OJDLabeledValue(
                OJDLocalized.string("controllers.server.source"),
                CommandLineName.kebab(record.serverSource)
              )
            }
          }
        }
        if device.physicalOwnership != .systemGamepad {
          // A per-controller identity resets the picker state on a new selection.
          Section {
            VirtualHIDProfileOverrideView(viewModel: viewModel, device: device).id(
              device.sessionToken.rawValue
            )
          }
          Section {
            VirtualGamepadActionsView(
              device: device,
              connectedDevices: connectedDevices,
              viewModel: viewModel,
              actions: actions
            )
          }
        }
        if let record {
          Section(header: Text(OJDLocalized.string("cli.controller.show.label.tuning"))) {
            tuningRows(for: record)
          }
        }
        Section { advancedDisclosure }
      }.task(id: recordLoadID) {
        let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
        record = await Task.detached { ControllerRecordSet.load().records[model] }.value
      }.sheet(item: $actions.timedKind) { kind in
        ControllerTimedActionSheet(
          kind: kind,
          device: device,
          gateway: viewModel.gateway,
          actions: actions
        )
      }.onReceive(actions.$pendingSave) { request in
        guard let request else { return }
        ControllerFilePanels.save(request) { actions.finishSave(to: $0) }
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

    /// Reloads the record when the controller or who serves its model changes.
    private var recordLoadID: String {
      "\(device.sessionToken.rawValue) \(device.recordServer.rawValue)"
    }

    private var connectedDevices: [ApplicationServiceDeviceDescription]? {
      if case .available(let status) = viewModel.statusState { return status.devices }
      return nil
    }

    /// The remapping profile active for the controller's model, if there is one.
    private var activeRemappingProfile: RemappingProfile? {
      guard case .available(let snapshot) = viewModel.remappingState,
        let active = snapshot.activeProfiles.routingActiveProfile(
          vendorID: device.vendorID,
          productID: device.productID
        )
      else { return nil }
      return snapshot.profiles.first { $0.id == active.profileID }
    }

    @ViewBuilder
    private func tuningRows(for record: ControllerRecord) -> some View {
      ForEach(ControllerTuningRows.rows(for: record, activeProfile: activeRemappingProfile)) {
        OJDLabeledValue($0.name, $0.text)
      }
    }

    private var wirelessDisconnectAction: some View {
      OJDLabeledRow(OJDLocalized.string("controllers.disconnectWireless")) {
        Button(OJDLocalized.string("controllers.disconnectWirelessButton")) {
          confirmsWirelessDisconnect = true
        }
      }
    }

    /// The identifiers and endpoints. The whole label row toggles, not only the chevron.
    private var advancedDisclosure: some View {
      DisclosureGroup(isExpanded: $showsAdvanced) {
        ForEach(ControllerDetailFacts.advanced(for: device, record: record)) { fact in
          OJDLabeledValue(fact.label, fact.value)
        }
        ControllerTimedActionRows(actions: actions)
      } label: {
        Button(OJDLocalized.string("virtualProfile.advanced")) { showsAdvanced.toggle() }
          .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
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
      OJDLabeledRow(OJDLocalized.string("inputTest.title")) {
        Button(OJDLocalized.string("inputTest.open")) {
          openInputTest(device)
        }.disabled(device.sessionState == .suspended)
      }
    }

    private var controllerSessionAction: some View {
      OJDLabeledRow(
        device.sessionState == .suspended
          ? OJDLocalized.string("controllers.suspended")
          : OJDLocalized.string("controllers.sessionActive")
      ) {
        if device.sessionState == .suspended {
          Button(OJDLocalized.string("controllers.resume")) {
            Task { @MainActor in await viewModel.resumeController(device) }
          }
        } else {
          Button(OJDLocalized.string("controllers.disconnectFromOJD")) {
            Task { @MainActor in await viewModel.suspendController(device) }
          }
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
          Text(connectionValue.displayText)
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

    var connectionValue: OJDValue { .reported(device.connection) }
  }

#endif
