#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Axis adjustment and capture

  struct AxisAdjustmentSheet: View {
    let binding: RemappingBinding
    let onSave: (RemappingAxisTuning) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var deadzone: Double
    @State
    private var gain: Double
    @State
    private var inverted: Bool
    @State
    private var curve: RemappingResponseCurve
    @State
    private var threshold: Double

    init(binding: RemappingBinding, onSave: @escaping (RemappingAxisTuning) -> Void) {
      self.binding = binding
      self.onSave = onSave
      let tuning = binding.axisTuning ?? .default
      _deadzone = State(initialValue: tuning.deadzone)
      _gain = State(initialValue: tuning.gain)
      _inverted = State(initialValue: tuning.inverted)
      _curve = State(initialValue: tuning.responseCurve)
      _threshold = State(initialValue: tuning.digitalActivationThreshold)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(
          OJDLocalized.formatted(
            "capture.adjust",
            RuntimePresentation.sourceLabel(binding.source)
          )
        ).font(.headline.weight(.semibold))
        SliderRow(
          title: OJDLocalized.string("capture.deadZone"),
          value: $deadzone,
          range: RemappingAxisTuning.deadzoneRange,
          suffix: "%"
        )
        SliderRow(
          title: OJDLocalized.string("capture.gain"),
          value: $gain,
          range: RemappingAxisTuning.gainRange,
          suffix: "×"
        )
        Toggle(OJDLocalized.string("capture.invertAxis"), isOn: $inverted)
        Picker(
          OJDLocalized.string("capture.responseCurve"),
          selection: $curve
        ) {
          ForEach(RemappingResponseCurve.allCases, id: \.self) { value in
            Text(responseCurveLabel(value)).tag(value)
          }
        }
        SliderRow(
          title: OJDLocalized.string("capture.digitalThreshold"),
          value: $threshold,
          range: RemappingAxisTuning.digitalActivationThresholdRange,
          suffix: "%"
        )
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save")) {
            onSave(
              RemappingAxisTuning(
                deadzone: deadzone,
                gain: gain,
                inverted: inverted,
                responseCurve: curve,
                digitalActivationThreshold: threshold
              )
            )
            presentationMode.wrappedValue.dismiss()
          }
        }
      }.padding(28).frame(width: 430)
    }

    private func responseCurveLabel(_ value: RemappingResponseCurve) -> String {
      switch value {
      case .linear: return OJDLocalized.string("capture.linear")
      case .easeIn: return OJDLocalized.string("capture.easeIn")
      case .easeOut: return OJDLocalized.string("capture.easeOut")
      case .smoothStep: return OJDLocalized.string("capture.smoothStep")
      }
    }
  }

  private struct SliderRow: View {
    let title: String
    @Binding
    var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(formattedValue).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Slider(value: $value, in: range)
      }
    }

    private var formattedValue: String {
      let percent = suffix == "%"
      let value = percent ? value * 100 : value
      return String(format: percent ? "%.0f%@" : "%.1f%@", value, suffix)
    }
  }

  struct ConflictBanner: View {
    let reload: () -> Void
    let keepEditing: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        Text(
          OJDLocalized.string(
            "error.profileChanged"
          )
        ).font(.subheadline.weight(.semibold))
        HStack(spacing: 10) {
          Button(OJDLocalized.string("common.reload")) { reload() }
          Button(OJDLocalized.string("common.keepEditing")) {
            keepEditing()
          }
        }
      }.padding(10).background(
        RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor))
      )
    }
  }

  enum ProfileNameValidation {
    static func trimmedName(_ name: String) -> String {
      name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

#endif
