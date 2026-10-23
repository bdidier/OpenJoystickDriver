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
    @State
    var showsTuning = false
    /// Counts the stick dead zone changes the service wrote, so the record is read again.
    @State
    var tuningChanges = 0
    /// The effective record of the controller's model, read from the record files.
    @State
    var record: ControllerRecord?
    @StateObject
    var actions = ControllerDetailActions()
  }

#endif
