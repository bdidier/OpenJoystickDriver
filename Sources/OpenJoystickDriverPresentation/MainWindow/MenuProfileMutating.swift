#if canImport(AppKit) && canImport(SwiftUI)

  /// The result of a profile mutation started from a menu.
  struct MenuProfileMutationOutcome {
    let result: RuntimeMutationResult
    /// The library's error text, shown for a conflict.
    let lastError: String?
  }

  /// Runs menu-started profile mutations under the Profiles editor's mutation tracking.
  @MainActor
  protocol MenuProfileMutating: MainWindowPresenting {
    /// Returns nil, without running `mutation`, when the editor holds a mutation.
    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome?
  }

#endif
