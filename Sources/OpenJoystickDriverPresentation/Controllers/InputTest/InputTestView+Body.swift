#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// One rumble motor's control. It observes the output settings itself, so its slider and
  /// value follow each change; rows built inside `ForEach` are not re-rendered by a parent
  /// that observes the settings.
  struct InputTestRumbleMotorControl: View {
    @ObservedObject
    var settings: InputTestOutputSettings
    let motor: PhysicalRumbleMotor
    let title: String
    let isBinary: Bool

    var body: some View {
      let value = Binding<Double>(
        get: { settings.rumbleIntensities[motor] ?? 0 },
        set: { settings.rumbleIntensities[motor] = $0 }
      )
      if isBinary {
        Toggle(
          title,
          isOn: Binding(get: { value.wrappedValue > 0 }, set: { value.wrappedValue = $0 ? 255 : 0 })
        )
      } else {
        InputTestSliderRow(title: title, valueText: "\(Int(value.wrappedValue.rounded()))") {
          Slider(value: value, in: 0...255)
        }
      }
    }
  }

  /// A slider on one form row: the title leads, the slider fills the trailing column and the
  /// value follows in a fixed-width monospaced-digit column so every slider ends at the same edge.
  struct InputTestSliderRow<Control: View>: View {
    let title: String
    let valueText: String
    let control: Control

    init(title: String, valueText: String, @ViewBuilder control: () -> Control) {
      self.title = title
      self.valueText = valueText
      self.control = control()
    }

    var body: some View {
      OJDLabeledRow(title) {
        HStack(spacing: 8) {
          control.labelsHidden().ojdAccessibilityLabel(title)
          Text(valueText)
            .font(.system(.body).monospacedDigit())
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .frame(width: 64, alignment: .trailing)
        }
      }
    }
  }

  extension InputTestView {
    var body: some View {
      Form {
        Section { controllerHeader }
        ForEach(model.visibleSections, id: \.self) { section in
          switch section {
          case .liveInput: Section { liveInput }
          case .motion:
            Section(header: Text(OJDLocalized.string("motion.calibration.title"))) {
              MotionCalibrationControls(model: model.motionCalibration)
            }
          case .rumble:
            Section(header: Text(OJDLocalized.string("inputTest.rumble"))) {
              InputTestOutputControlsView(settings: model.outputSettings) {
                rumbleContent
                if outputErrorBelongs(to: [.rumble]) { outputErrorView }
              }
            }
          case .lighting:
            Section(header: Text(OJDLocalized.string("inputTest.lighting"))) {
              InputTestOutputControlsView(settings: model.outputSettings) {
                lightingContent
                if outputErrorBelongs(to: [.playerIndicator, .color, .brightness]) {
                  outputErrorView
                }
              }
            }
          }
        }
      }.ojdGroupedForm().onReceive(runtimeViewModel.$statusState) { state in
        guard case .available(let status) = state else { return }
        model.reconcileStatus(status)
      }
    }

    private var controllerHeader: some View {
      HStack(spacing: 10) {
        OJDSystemSymbol(name: statusSemanticState.presentation.symbolName, fallback: statusLabel)
          .foregroundColor(Color(statusSemanticState.presentation.tone.color))
          .accessibilityHidden(true)
        Text(statusLabel).font(.subheadline.weight(.semibold))
        if let device = model.device {
          Text(
            "\(OJDValue.reported(device.connection).displayText) · "
              + "\(device.protocolBinding.displayLabel) · "
              + usbIdentifier(device).displayText
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer()
      }.accessibilityElement(children: .combine).ojdAccessibilityLabel(
        OJDLocalized.string("inputTest.status")
      ).ojdAccessibilityValue(statusLabel)
    }

    private var publishedProfile: VirtualDeviceProfile {
      model.device?.publishedVirtualProfile ?? .generic
    }

    var liveInput: some View {
      InputTestLiveInputView(liveState: model.liveState, publishedProfile: publishedProfile)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var rumbleContent: some View {
      if model.capabilities.supportsRumble {
        Group {
          ForEach(model.capabilities.rumbleMotors, id: \.self) { rumbleControl(for: $0) }
          InputTestSliderRow(
            title: OJDLocalized.string("inputTest.duration"),
            valueText: OJDLocalized.formatted(
              "inputTest.durationValue",
              Int(model.rumbleDurationMilliseconds)
            )
          ) {
            Slider(
              value: rumbleDurationBinding,
              in: Double(
                InputTestViewModel.rumbleDurationRange.lowerBound
              )...Double(
                InputTestViewModel.rumbleDurationRange.upperBound
              ),
              step: 50
            )
          }
        }.disabled(!model.canSendOutput || model.isOutputBusy)
        HStack(spacing: 8) {
          Button(OJDLocalized.string("inputTest.testRumble")) {
            model.testRumble()
          }.disabled(!model.canSendOutput || model.isOutputBusy)
          Button(OJDLocalized.string("common.stop")) { model.stopRumble() }
            .disabled(!model.canStopRumble)
          Spacer()
          outputStatus(for: .rumble)
        }
      } else {
        unavailableOutputLabel(OJDLocalized.string("inputTest.rumbleUnavailable"))
      }
    }

    @ViewBuilder
    private var lightingContent: some View {
      Group {
        if model.capabilities.supportsPlayerIndicator {
          VStack(alignment: .leading, spacing: 6) {
            Text(OJDLocalized.string("inputTest.playerIndicator"))
            Picker("", selection: playerIndicatorBinding) {
              Text(OJDLocalized.string("inputTest.off")).tag(PhysicalPlayerIndicator.off)
              Text("1").tag(PhysicalPlayerIndicator.player1)
              Text("2").tag(PhysicalPlayerIndicator.player2)
              Text("3").tag(PhysicalPlayerIndicator.player3)
              Text("4").tag(PhysicalPlayerIndicator.player4)
            }.pickerStyle(.segmented).labelsHidden()
            Button(OJDLocalized.string("common.apply")) { model.applyPlayerIndicator() }
          }
        }
        if model.capabilities.lightingFeatures.contains(.programmableColor) {
          OJDLabeledRow(OJDLocalized.string("inputTest.color")) {
            HStack {
              OJDPhysicalColorWell(color: colorBinding).frame(width: 44, height: 24)
              Button(OJDLocalized.string("common.apply")) { model.applyColor() }
            }
          }
        }
        if model.capabilities.supportsProgrammableBrightness {
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(OJDLocalized.string("inputTest.brightness"))
              Spacer()
              Text("\(Int(model.brightness.rounded()))").font(
                .system(.caption, design: .monospaced)
              )
            }
            HStack {
              Slider(value: brightnessBinding, in: 0...255)
              Button(OJDLocalized.string("common.apply")) { model.applyBrightness() }
            }
          }
        }
      }.disabled(!model.canSendOutput || model.isOutputBusy)
    }

    private func outputErrorBelongs(to operations: Set<InputTestViewModel.OutputOperation>) -> Bool
    {
      guard case .failed(let operation) = model.outputState else { return false }
      return operations.contains(operation)
    }

    @ViewBuilder
    private var outputErrorView: some View {
      if let error = model.outputError {
        Text(error).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
          horizontal: false,
          vertical: true
        ).ojdAccessibilityLabel(
          OJDLocalized.string("inputTest.outputError")
        )
      }
    }

    private func rumbleControl(for motor: PhysicalRumbleMotor) -> some View {
      InputTestRumbleMotorControl(
        settings: model.outputSettings,
        motor: motor,
        title: motor.title,
        isBinary: model.capabilities.binaryRumbleMotors.contains(motor)
      )
    }

    private func unavailableOutputLabel(_ message: String) -> some View {
      Text(message).foregroundColor(Color(NSColor.secondaryLabelColor))
    }

    @ViewBuilder
    private func outputStatus(for operation: InputTestViewModel.OutputOperation) -> some View {
      switch model.outputState {
      case .running(let current) where current == operation: ProgressView()
      case .succeeded(let current) where current == operation:
        Text(OJDLocalized.string("common.done")).foregroundColor(
          Color(SemanticState.healthy.presentation.tone.color)
        )
      case .failed(let current) where current == operation:
        Text(OJDLocalized.string("common.failed")).foregroundColor(
          Color(SemanticState.failure.presentation.tone.color)
        )
      default: EmptyView()
      }
    }

    private var colorBinding: Binding<NSColor> {
      Binding(
        get: {
          NSColor(
            calibratedRed: model.red / 255,
            green: model.green / 255,
            blue: model.blue / 255,
            alpha: 1
          )
        },
        set: { color in
          let converted = color.usingColorSpace(.deviceRGB) ?? color
          model.red = Double(converted.redComponent * 255)
          model.green = Double(converted.greenComponent * 255)
          model.blue = Double(converted.blueComponent * 255)
        }
      )
    }

    private var rumbleDurationBinding: Binding<Double> {
      Binding(
        get: { model.rumbleDurationMilliseconds },
        set: { model.rumbleDurationMilliseconds = $0 }
      )
    }

    private var playerIndicatorBinding: Binding<PhysicalPlayerIndicator> {
      Binding(get: { model.playerIndicator }, set: { model.playerIndicator = $0 })
    }

    private var brightnessBinding: Binding<Double> {
      Binding(get: { model.brightness }, set: { model.brightness = $0 })
    }
  }

#endif
