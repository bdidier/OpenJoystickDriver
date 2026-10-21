#if canImport(AppKit) && canImport(SwiftUI)

  import Foundation

  /// A profile change the status menu and the Profile menu can start.
  enum StatusItemProfileOperation: Equatable {
    case activate(profileID: UUID)
    case deactivate(profileID: UUID)

    var request: RuntimeMutationRequest {
      switch self {
      case .activate(let profileID):
        return RuntimeMutationRequest(operation: .activate(profileID: profileID))
      case .deactivate(let profileID):
        return RuntimeMutationRequest(operation: .deactivate(profileID: profileID))
      }
    }

    /// Runs the operation on the window's shared library under the editor's mutation tracking.
    /// Returns nil, without running it, when the editor holds a mutation.
    @MainActor
    func perform(on window: any MenuProfileMutating) async -> MenuProfileMutationOutcome? {
      let request = self.request
      return await window.performMenuProfileMutation(request) { library in
        switch self {
        case .activate(let profileID):
          return await library.activateRemappingProfile(id: profileID, request: request)
        case .deactivate(let profileID):
          return await library.deactivateRemappingProfile(profileID: profileID, request: request)
        }
      }
    }
  }

#endif
