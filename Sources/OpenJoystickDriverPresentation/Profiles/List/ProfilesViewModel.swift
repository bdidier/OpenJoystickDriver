#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UniformTypeIdentifiers

  actor ProfileDocumentService {
    func load(from url: URL) throws -> RemappingProfile {
      try RemappingProfileFileStore.load(from: url)
    }

    func write(_ profile: RemappingProfile, to url: URL) throws {
      try RemappingProfileFileStore.write(profile, to: url)
    }
  }

  @MainActor
  final class ProfilesViewModel: ObservableObject {
    let documents: ProfileDocumentService
    let capabilityRegistry = ProtocolDriverRegistry()
    @Published
    var selectedProfileID: UUID?
    @Published
    var selectedRecoveryIssueID: UUID?
    @Published
    var isCreatingProfile = false
    @Published
    var activeAlert: ProfilesAlert?
    @Published
    var profileActionError: String?
    @Published
    var pairingProfile: RemappingProfile?
    /// A profile read from a file the person chose, waiting for the Profiles screen to import it
    /// through the editor's discard and mutation checks.
    @Published
    var chosenImportProfile: RemappingProfile?
    @Published
    var selectedEditorSection = ProfilePresentationPolicy.defaultSection

    @Published
    var editorTransition = ProfileEditorTransitionState()
    var observedDiscardGeneration = 0
    var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload?
    var preservedEditorProfile: RemappingProfile?
    var editorGeneration = 0
    private var editorViewModel: ProfileEditorViewModel?
    private var editorViewModelGeneration: (discard: Int, refresh: Int)?

    init(documents: ProfileDocumentService = ProfileDocumentService()) {
      self.documents = documents
    }

    /// Whether profile creation, import, delete and the like must wait: a mutation or recovery is
    /// running, or the library has damaged entries. The Profiles screen and the toolbar share this.
    func isActionBlocked(library: ProfileLibraryModel, runtime: RuntimeViewModel) -> Bool {
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      if case .available(let current) = runtime.remappingState {
        snapshot = current
      } else {
        snapshot = lastKnownSnapshot
      }
      return library.activeMutationOperation != nil || editorTransition.isEditingBlocked
        || library.profileRecoveryInFlight || !(snapshot?.profileIssues.isEmpty ?? true)
    }

    /// Asks for a profile file and reads it into ``chosenImportProfile``.
    func chooseProfileToImport() {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = OJDLocalized.string("profiles.import")
      panel.allowedContentTypes = [.json]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          chosenImportProfile = try await documents.load(from: url)
          profileActionError = nil
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    /// Asks where to save `profile` and writes it there.
    func exportProfile(_ profile: RemappingProfile) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("profiles.export")
      panel.nameFieldStringValue = "\(profile.name).json"
      panel.allowedContentTypes = [.json]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          try await documents.write(profile, to: url)
          profileActionError = nil
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    func editor(for profile: RemappingProfile, discardGeneration: Int) -> ProfileEditorViewModel {
      let generation = (discard: discardGeneration, refresh: editorGeneration)
      if let editorViewModel, editorViewModel.expectedCurrent.id == profile.id,
        editorViewModelGeneration?.discard == generation.discard,
        editorViewModelGeneration?.refresh == generation.refresh
      {
        return editorViewModel
      }
      let editor = ProfileEditorViewModel(profile: profile)
      editorViewModel = editor
      editorViewModelGeneration = generation
      return editor
    }

    func resetEditor() {
      editorViewModel = nil
      editorViewModelGeneration = nil
    }

    func reconcileSelection(with snapshot: ApplicationServiceRemappingSnapshotPayload) {
      if let selectedRecoveryIssueID,
        !snapshot.profileIssues.contains(where: { $0.id == selectedRecoveryIssueID })
      {
        self.selectedRecoveryIssueID = nil
      }
      if let selectedProfileID, !snapshot.profiles.contains(where: { $0.id == selectedProfileID }) {
        self.selectedProfileID = snapshot.profiles.first?.id
      }
      if selectedProfileID == nil, selectedRecoveryIssueID == nil {
        selectedProfileID = snapshot.profiles.first?.id
        if selectedProfileID == nil { selectedRecoveryIssueID = snapshot.profileIssues.first?.id }
      }
    }
  }

  @MainActor
  final class ProfileEditorViewModel: ObservableObject {
    @Published
    var draft: RuntimeProfileDraft
    @Published
    var activeSheet: ProfileEditorSheet?
    @Published
    var showingConflict = false
    @Published
    var localError: String?
    @Published
    var saveError: String?

    @Published
    var expectedCurrent: RemappingProfile
    @Published
    var saveState = ProfileEditorSaveState()

    init(profile: RemappingProfile) {
      draft = RuntimeProfileDraft(profile: profile)
      expectedCurrent = profile
    }
  }

#endif
