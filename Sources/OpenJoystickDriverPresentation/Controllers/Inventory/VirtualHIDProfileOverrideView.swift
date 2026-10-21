#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The override of one controller model's virtual HID profile, matching
  /// `ojd virtual set|reset`: Automatic clears the override.
  struct VirtualHIDProfileOverrideView: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let device: ApplicationServiceDeviceDescription
    @State
    private var scope: VirtualHIDProfileScopeChoice

    init(viewModel: RuntimeViewModel, device: ApplicationServiceDeviceDescription) {
      self.viewModel = viewModel
      self.device = device
      _scope = State(initialValue: VirtualHIDProfileScopeChoice.initial(for: device))
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          OJDLocalized.string("virtualProfile.title"),
          selection: overrideBinding
        ) {
          Text(OJDLocalized.string("mapping.automatic")).tag(
            VirtualHIDProfileID?.none
          )
          ForEach(VirtualHIDProfileID.allCases, id: \.self) { profile in
            Text("\(profile.identity.productName) (\(profile.rawValue))").tag(
              VirtualHIDProfileID?.some(profile)
            )
          }
        }.disabled(overrideState.inFlight)
        if VirtualHIDProfileScopeChoice.offered(for: device).count > 1 {
          Picker(OJDLocalized.string("controllers.virtual.scope"), selection: $scope) {
            ForEach(VirtualHIDProfileScopeChoice.offered(for: device), id: \.self) { choice in
              Text(OJDLocalized.string(choice.titleKey)).tag(choice)
            }
          }.disabled(overrideState.inFlight)
        } else {
          Text(OJDLocalized.string("virtualProfile.modelScope")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
        }
        if overrideState.inFlight {
          HStack(spacing: 8) {
            ProgressView()
            Text(updatingLabel).foregroundColor(Color(NSColor.secondaryLabelColor))
          }.ojdAccessibilityLabel(updatingLabel)
        }
        ForEach(problems, id: \.self) { message in
          HStack(alignment: .top, spacing: 8) {
            OJDSystemSymbol(
              name: SemanticState.failure.presentation.symbolName,
              fallback: OJDLocalized.string("common.needsAttention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }.ojdAccessibilityLabel(
            OJDLocalized.string("common.needsAttention")
          ).ojdAccessibilityValue(message)
        }
      }
    }

    /// Shared by every connected controller of this model, like the override itself.
    private var overrideState: RuntimeVirtualHIDProfileOverrideState {
      viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(device)]
        ?? RuntimeVirtualHIDProfileOverrideState()
    }

    private var overrideBinding: Binding<VirtualHIDProfileID?> {
      Binding(
        get: {
          // Show the pending choice until the refreshed status reports the stored override.
          if let request = overrideState.request { return request.requested }
          return device.virtualHIDProfile?.override
        },
        set: { profile in
          guard profile != device.virtualHIDProfile?.override else { return }
          let device = device
          let scope = scope.scope
          Task { @MainActor in
            await viewModel.setVirtualHIDProfileOverride(profile, for: device, scope: scope)
          }
        }
      )
    }

    private var updatingLabel: String {
      OJDLocalized.string("virtualProfile.updating")
    }

    private var problems: [String] {
      var messages = overrideState.failure.map { [$0] } ?? []
      if case .available(let status) = viewModel.statusState {
        messages += status.virtualHIDProfileOverrideStoreMessages
      }
      return messages
    }
  }

#endif
