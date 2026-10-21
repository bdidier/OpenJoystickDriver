#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  struct ControllerDetailView: View {
    let device: ApplicationServiceDeviceDescription
    let activeProfile: RuntimeActiveProfileState
    let retry: () -> Void
    @ObservedObject
    var viewModel: RuntimeViewModel
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
    @State
    var serialVisibility = SerialNumberVisibility()
    @State
    var showsAdvanced = false
    /// The effective record of the controller's model, read from the record files.
    @State
    var record: ControllerRecord?
    @StateObject
    var actions = ControllerDetailActions()
  }

#endif
