#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {

    var profileListSelection: Binding<ProfileListSelection?> {
      Binding(
        get: {
          if let selectedRecoveryIssueID { return .issue(selectedRecoveryIssueID) }
          return selectedProfileID.map(ProfileListSelection.profile)
        },
        set: { selection in
          switch selection {
          case .profile(let profileID):
            selectedRecoveryIssueID = nil
            selectProfile(profileID)
          case .issue(let issueID): selectedRecoveryIssueID = issueID
          case nil: break
          }
        }
      )
    }

    @ViewBuilder
    var profileDetail: some View {
      if let selectedRecoveryIssue {
        profileRecoveryDetail(selectedRecoveryIssue)
      } else if let selectedProfile {
        VStack(alignment: .leading, spacing: 0) {
          refreshStatus
          if selectedProfile.joyConPair != nil { joyConPairControls(selectedProfile) }
          ProfileEditorView(
            profile: selectedProfile,
            capabilities: ProfileCapabilityResolver.resolve(
              profile: selectedProfile,
              connectedDevices: connectedDevices,
              registry: screen.capabilityRegistry
            ) ?? .unknown,
            editor: screen.editor(
              for: selectedProfile,
              discardGeneration: navigation.discardGeneration
            ),
            viewModel: viewModel,
            library: library,
            isActive: isActive(selectedProfile),
            isEditingBlocked: profileEditorTransition.isEditingBlocked
              || profileLibraryNeedsRecovery,
            selectedSection: $screen.selectedEditorSection,
            onEditingStateChanged: { setEditorDirty($0) },
            onMutationStarted: { beginProfileMutation($0) },
            onMutationResult: { handleProfileMutationResult($0) }
          ).id(
            selectedProfile.id.uuidString + "-\(navigation.discardGeneration)"
              + "-\(profileEditorGeneration)"
          )
        }
      } else {
        switch viewModel.remappingState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string("ui.profiles.loading")
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string("ui.profiles.unavailable"),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.profiles.loadError"
            ),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .available: noProfilesState
        }
      }
    }

    private func profileRecoveryDetail(
      _ issue: ApplicationServiceRemappingProfileIssue
    ) -> some View {
      let presentation = ProfileIssuePresentation(issue)
      return Form {
        Section(header: Text(presentation.titleWithCode)) {
          Text(presentation.message).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .ojdAccessibilityLabel(presentation.title)
            .ojdAccessibilityValue(presentation.accessibilityValue)
          Button(
            OJDLocalized.string(
              issue.kind == .damagedProfile
                ? "ui.profiles.deleteDamagedButton" : "ui.profiles.resetLibraryButton"
            )
          ) {
            activeAlert =
              issue.kind == .damagedProfile
              ? .deleteDamagedProfile(issue.id) : .resetLibrary(issue.id)
          }.disabled(library.profileRecoveryInFlight)
        }
      }.ojdGroupedForm()
    }

    @ViewBuilder
    func joyConPairControls(_ profile: RemappingProfile) -> some View {
      let sessions = currentSnapshot?.joyConPairs.filter { $0.profileID == profile.id } ?? []
      HStack(spacing: 10) {
        Text(OJDLocalized.string("ui.profiles.joyConPair")).font(
          .caption.weight(.semibold)
        )
        if sessions.isEmpty {
          Button(
            OJDLocalized.string("ui.profiles.pairJoyCons")
          ) { pairingProfile = profile }.disabled(!hasAvailableJoyConPair || isProfileActionBlocked)
        } else {
          Text(OJDLocalized.string("ui.profiles.joyConPairActive")).font(
            .caption
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
          ForEach(sessions, id: \.sessionID) { session in
            Button(OJDLocalized.string("ui.profiles.unpairJoyCons")) {
              Task { @MainActor in
                profileActionError = await viewModel.unpairRemappingJoyCons(
                  sessionID: session.sessionID
                )
              }
            }.disabled(isProfileActionBlocked)
          }
        }
        Spacer()
      }.padding(.horizontal, 28).padding(.top, 10)
    }

    var currentSnapshot: ApplicationServiceRemappingSnapshotPayload? {
      if case .available(let snapshot) = viewModel.remappingState { return snapshot }
      return lastKnownSnapshot
    }

    var hasAvailableJoyConPair: Bool {
      connectedDevices.contains {
        JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .left
      }
        && connectedDevices.contains {
          JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .right
        }
    }

    var noProfilesState: some View {
      EmptyStateView(
        symbol: "slider.horizontal.3",
        title: OJDLocalized.string("ui.profiles.none"),
        message: OJDLocalized.string("ui.profiles.createMessage")
      )
    }

    func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("ui.profiles.assignments", count: count)
    }

    func profileAccessibilityValue(_ profile: RemappingProfile) -> String {
      let count = assignmentCountLabel(profile.bindings.count)
      guard isActive(profile) else { return count }
      return OJDLocalized.formatted("ui.profiles.activeAssignmentCount", count)
    }

    @ViewBuilder
    var refreshStatus: some View {
      switch viewModel.remappingState {
      case .loading:
        HStack(spacing: 8) {
          ProgressView()
          Text(OJDLocalized.string("ui.profiles.refreshing"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(.horizontal, 28).padding(.top, 14)
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "ui.profiles.stateUnavailable"
          ),
          message: OJDLocalized.formatted(
            "ui.profiles.draftPreserved",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .error(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "ui.profiles.refreshError"
          ),
          message: OJDLocalized.formatted(
            "ui.profiles.draftPreserved",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .available: EmptyView()
      }
    }

  }

#endif
