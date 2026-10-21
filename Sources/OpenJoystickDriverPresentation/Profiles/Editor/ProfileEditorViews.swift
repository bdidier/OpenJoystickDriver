#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Profile editor

  struct ProfileEditorView: View {
    let profile: RemappingProfile
    let capabilities: ControllerProfileCapabilities
    @ObservedObject
    var editor: ProfileEditorViewModel
    @ObservedObject
    var viewModel: RuntimeViewModel
    @ObservedObject
    var library: ProfileLibraryModel
    let isActive: Bool
    let isEditingBlocked: Bool
    @Binding
    var selectedSection: ProfileEditorSection
    let onEditingStateChanged: (Bool) -> Void
    let onMutationStarted: (RuntimeMutationRequest) -> Bool
    let onMutationResult: (RuntimeMutationResult) -> Void
    @State
    var confirmation: ProfileEditorConfirmation?

    init(
      profile: RemappingProfile,
      capabilities: ControllerProfileCapabilities,
      editor: ProfileEditorViewModel,
      viewModel: RuntimeViewModel,
      library: ProfileLibraryModel,
      isActive: Bool,
      isEditingBlocked: Bool,
      selectedSection: Binding<ProfileEditorSection>,
      onEditingStateChanged: @escaping (Bool) -> Void,
      onMutationStarted: @escaping (RuntimeMutationRequest) -> Bool,
      onMutationResult: @escaping (RuntimeMutationResult) -> Void
    ) {
      self.profile = profile
      self.capabilities = capabilities
      self.editor = editor
      self.viewModel = viewModel
      self.library = library
      self.isActive = isActive
      self.isEditingBlocked = isEditingBlocked
      _selectedSection = selectedSection
      self.onEditingStateChanged = onEditingStateChanged
      self.onMutationStarted = onMutationStarted
      self.onMutationResult = onMutationResult
    }
  }

  enum ProfileEditorConfirmation: Identifiable {
    case activateEmpty
    case clearInputs
    case removeAllAssignments

    var id: String {
      switch self {
      case .activateEmpty: "activate-empty"
      case .clearInputs: "clear-inputs"
      case .removeAllAssignments: "remove-all-assignments"
      }
    }
  }

#endif
