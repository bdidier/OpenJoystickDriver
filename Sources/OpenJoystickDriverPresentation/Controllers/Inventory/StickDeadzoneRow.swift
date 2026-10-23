#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The stick dead zone of one controller model: a stepper over the value, and a button that
  /// removes the user's value. Each change goes to the service, which rewrites the user record.
  /// Both controls stay disabled until the record has been read again.
  struct StickDeadzoneRow: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let device: ApplicationServiceDeviceDescription
    let setting: StickDeadzoneSetting
    /// Reads the record again after the service wrote it.
    let reload: () async -> Void
    @StateObject
    private var editor = StickDeadzoneEditor()

    var body: some View {
      OJDLabeledRow(OJDLocalized.string("ui.controllers.stickDeadzone.label")) {
        HStack {
          Text(setting.text).foregroundColor(Color(NSColor.secondaryLabelColor))
          Stepper(
            OJDLocalized.string("ui.controllers.stickDeadzone.label"),
            onIncrement: setting.increased.map { value in { change(to: value) } },
            onDecrement: setting.decreased.map { value in { change(to: value) } }
          ).labelsHidden()
          if setting.canReset {
            Button(OJDLocalized.string("action.reset")) { change(to: nil) }
          }
        }.disabled(editor.isWriting)
      }
    }

    private func change(to value: Double?) {
      Task { @MainActor in
        await editor.change(to: value, for: device, viewModel: viewModel, reload: reload)
      }
    }
  }

#endif
