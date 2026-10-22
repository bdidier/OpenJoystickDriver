#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// Who serves one controller model, macOS natively or OpenJoystickDriver as a virtual controller,
  /// matching `ojd controller claim` and `release`. A change goes to the service, which rewrites
  /// the user record and re-applies it to the connected controller.
  struct ControllerServerPicker: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let device: ApplicationServiceDeviceDescription

    /// Whether the picker applies to `device`: macOS serves it natively, or its record already
    /// gives it to OpenJoystickDriver, and its family does not use raw USB, which always belongs
    /// to OpenJoystickDriver.
    static func isShown(for device: ApplicationServiceDeviceDescription) -> Bool {
      ServingPolicy.offersServerChoice(ServingInput(device))
    }

    var body: some View {
      Picker(OJDLocalized.string("ui.controllers.server.label"), selection: serverBinding) {
        Text(OJDLocalized.string("platform.macos.ui.controllers.server.system")).tag(
          ControllerServer.system
        )
        Text(OJDLocalized.string("ui.controllers.server.ojd")).tag(ControllerServer.ojd)
      }.pickerStyle(.segmented)
    }

    private var serverBinding: Binding<ControllerServer> {
      Binding(
        get: { viewModel.shownControllerServer(for: device) },
        set: { server in
          guard server != viewModel.shownControllerServer(for: device) else { return }
          let device = device
          Task { @MainActor in await viewModel.setControllerServer(server, for: device) }
        }
      )
    }
  }

#endif
