#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The stick dead zone of one controller model: a stepper over the value, and a button that
  /// removes the user's value. Each change goes to the service, which rewrites the user record.
  struct StickDeadzoneRow: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let device: ApplicationServiceDeviceDescription
    let setting: StickDeadzoneSetting
    /// Called after the service wrote the record, so the detail reads it again.
    let didChange: () -> Void

    var body: some View {
      OJDLabeledRow(OJDLocalized.string("ui.controllers.stickDeadzone.label")) {
        HStack {
          Text(setting.text).foregroundColor(Color(NSColor.secondaryLabelColor))
          Stepper(
            OJDLocalized.string("ui.controllers.stickDeadzone.label"),
            onIncrement: { change(to: setting.increased) },
            onDecrement: { setting.decreased.map { change(to: $0) } }
          ).labelsHidden()
          if setting.canReset {
            Button(OJDLocalized.string("action.reset")) { change(to: nil) }
          }
        }
      }
    }

    private func change(to value: Double?) {
      let device = device
      Task { @MainActor in
        if await viewModel.setStickDeadzone(value, for: device) { didChange() }
      }
    }
  }

#endif
