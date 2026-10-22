#if canImport(SwiftUI) && canImport(AppKit)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The virtual gamepad actions of one controller: export its mapping, launch a game with it,
  /// and return every override to automatic.
  struct VirtualGamepadActionsView: View {
    let device: ApplicationServiceDeviceDescription
    /// Every connected controller; nil while the service status is not available.
    let connectedDevices: [ApplicationServiceDeviceDescription]?
    @ObservedObject
    var viewModel: RuntimeViewModel
    @ObservedObject
    var actions: ControllerDetailActions
    @State
    private var confirmsResetAll = false
    @State
    private var resetAllFailure: String?

    var body: some View {
      Group {
        if let profile = VirtualGamepadExport.profile(for: device) {
          OJDLabeledRow(OJDLocalized.string("ui.controllers.exportMapping")) {
            Button(OJDLocalized.string("action.export")) { export(profile) }
          }
          launchRows

          if let outcome = actions.launchOutcome {
            ControllerNoticeText(text: outcome.message, isError: isFailure(outcome))
          }
        }
        OJDLabeledRow(OJDLocalized.string("ui.controllers.virtual.resetAll")) {
          Button(OJDLocalized.string("action.reset")) { confirmsResetAll = true }
        }
        if let failure = resetAllFailure { ControllerNoticeText(text: failure, isError: true) }
        if let notice = actions.notice, notice.source == .exportMapping {
          ControllerNoticeText(text: notice.text, isError: notice.isError)
        }
      }.alert(isPresented: $confirmsResetAll) {
        Alert(
          title: Text(OJDLocalized.string("cli.virtual.reset.allSummary")),
          primaryButton: .destructive(Text(OJDLocalized.string("action.reset"))) {
            Task { @MainActor in
              resetAllFailure = await viewModel.resetAllVirtualHIDProfileOverrides()
            }
          },
          secondaryButton: .cancel()
        )
      }
    }

    @ViewBuilder
    private var launchRows: some View {
      OJDLabeledRow(OJDLocalized.string("ui.controllers.launch")) {
        if connectedDevices == nil {
          Text(OJDLocalized.string("status.unavailable"))
        } else {
          Button(OJDLocalized.string("ui.controllers.launch.prompt")) { launch() }
        }
      }
      if let devices = connectedDevices {
        let needed = Result { try VirtualGamepadLaunch.profilesNeedingBackend(in: devices) }
        switch needed {
        case .success(let profiles):
          ForEach(profiles, id: \.self) { profile in
            Text(
              OJDLocalized.formatted(
                "cli.virtual.group.sdlHintsNote",
                CommandLineName.kebab(profile.rawValue)
              )
            ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        case .failure(let error):
          ControllerNoticeText(text: RuntimePresentation.userFacingError(error), isError: true)
        }
      }
    }

    private func isFailure(_ outcome: VirtualGamepadLaunch.Outcome) -> Bool {
      if case .failed = outcome { return true }
      return false
    }

    private func export(_ profile: VirtualHIDProfileID) {
      actions.clearNotice()
      ControllerFilePanels.exportMapping(profile: profile) { choice in
        guard let choice else { return }
        actions.exportMapping(format: choice.format, profile: profile, to: choice.url)
      }
    }

    private func launch() {
      guard let connectedDevices else { return }
      ControllerFilePanels.chooseProgram { choice in
        guard let choice else { return }
        actions.launch(
          program: choice.program,
          devices: connectedDevices,
          gameControllerBackend: choice.gameControllerBackend
        )
      }
    }
  }

  /// A result line under an action; a failure is red with the failure symbol.
  struct ControllerNoticeText: View {
    let text: String
    let isError: Bool

    var body: some View {
      Text(text).font(.caption).foregroundColor(
        isError
          ? Color(SemanticState.failure.presentation.tone.color)
          : Color(NSColor.secondaryLabelColor)
      ).fixedSize(horizontal: false, vertical: true)
    }
  }

  /// The Capture Packets and Draft Record buttons, under Advanced.
  struct ControllerTimedActionRows: View {
    @ObservedObject
    var actions: ControllerDetailActions

    var body: some View {
      Group {
        Button(OJDLocalized.string("ui.controllers.capturePackets")) {
          actions.clearNotice()
          actions.timedKind = .capturePackets
        }
        Button(OJDLocalized.string("ui.controllers.draftRecord")) {
          actions.clearNotice()
          actions.timedKind = .draftRecord
        }
        if let notice = actions.notice, notice.source == .timedCapture {
          ControllerNoticeText(text: notice.text, isError: notice.isError)
        }
      }
    }
  }

  /// The sheet of a timed capture: the duration, the instruction, and the progress.
  struct ControllerTimedActionSheet: View {
    let kind: ControllerDetailActions.TimedKind
    let device: ApplicationServiceDeviceDescription
    let gateway: any ControllerDiagnosticsGateway
    @ObservedObject
    var actions: ControllerDetailActions
    @State
    private var durationText = CaptureDuration.text(for: CaptureDuration.defaultSeconds)

    private var seconds: Double? { CaptureDuration.parse(durationText) }

    private var identity: String {
      String(format: "%04X:%04X", device.vendorID, device.productID)
    }

    private var isCapturing: Bool { actions.timedState == .capturing }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          OJDLocalized.string(
            kind == .draftRecord
              ? "ui.controllers.draftRecord.title" : "ui.controllers.capturePackets.title"
          )
        ).font(.headline)
        Text(instruction).fixedSize(horizontal: false, vertical: true)
        if kind == .capturePackets {
          Text(OJDLocalized.string("ui.developer.packetSharingWarning")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        HStack {
          Text(OJDLocalized.string("ui.controllers.captureDuration"))
          TextField("", text: $durationText).frame(width: 80).multilineTextAlignment(.trailing)
            .disabled(isCapturing)
            .ojdAccessibilityLabel(OJDLocalized.string("ui.controllers.captureDuration"))
        }
        if seconds == nil {
          ControllerNoticeText(
            text: OJDLocalized.string("ui.controllers.captureDurationInvalid"),
            isError: true
          )
        }
        if case .failed(let message) = actions.timedState {
          ControllerNoticeText(text: message, isError: true)
        }
        HStack {
          if isCapturing {
            ProgressView().controlSize(.small)
            Text(OJDLocalized.string("ui.developer.capturing"))
          }
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { actions.cancelTimed() }
            .keyboardShortcut(.cancelAction)
          Button(OJDLocalized.string("ui.developer.startCapture")) { start() }
            .keyboardShortcut(.defaultAction).disabled(seconds == nil || isCapturing)
        }
      }.padding(20).frame(width: 420)
    }

    private var instruction: String {
      OJDLocalized.formatted(
        kind == .draftRecord ? "cli.record.draft.started" : "cli.controller.capture.started",
        device.name,
        identity
      )
    }

    private func start() {
      guard let seconds else { return }
      let device = device
      actions.startTimed(
        kind,
        device: device,
        gateway: gateway,
        seconds: seconds
      ) { ControllerRecordDrafting.physicalDescriptor(for: device) }
    }
  }

#endif
