#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// Who serves one controller model, macOS natively or OpenJoystickDriver as a virtual controller,
  /// matching `ojd controller ownership`. A change goes to the service, which rewrites the user
  /// record and re-applies it to the connected controller.
  struct ControllerOwnershipPicker: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let device: ApplicationServiceDeviceDescription

    /// Whether the picker applies to `device`: macOS serves it natively, or its record already
    /// gives it to OpenJoystickDriver, and its family does not use raw USB, which always belongs
    /// to OpenJoystickDriver.
    static func isShown(for device: ApplicationServiceDeviceDescription) -> Bool {
      (device.physicalOwnership == .nativeGamepad || device.recordServer == .ojd)
        && device.discoverySource != .rawUSB
    }

    var body: some View {
      Picker(OJDLocalized.string("controllers.ownership.label"), selection: ownershipBinding) {
        Text(OJDLocalized.string("controllers.ownership.native")).tag(ControllerServer.system)
        Text(OJDLocalized.string("controllers.ownership.virtual")).tag(ControllerServer.ojd)
      }.pickerStyle(.segmented)
    }

    private var ownershipBinding: Binding<ControllerServer> {
      Binding(
        get: { device.recordServer },
        set: { ownership in
          guard ownership != device.recordServer else { return }
          let device = device
          Task { @MainActor in await viewModel.setControllerOwnership(ownership, for: device) }
        }
      )
    }
  }

#endif
