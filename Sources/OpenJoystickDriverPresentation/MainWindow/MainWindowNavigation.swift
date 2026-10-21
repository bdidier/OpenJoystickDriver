#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit

  protocol MainWindowAreaPersistence {
    func loadArea() -> MainWindowArea?
    func saveArea(_ area: MainWindowArea)
  }

  /// Remembers the selected area between launches. It is window state, not a setting.
  struct UserDefaultsMainWindowAreaPersistence: MainWindowAreaPersistence {
    static let key = "OpenJoystickDriver.mainWindow.lastArea"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadArea() -> MainWindowArea? {
      guard let rawValue = defaults.string(forKey: Self.key) else { return nil }
      return MainWindowArea(rawValue: rawValue)
    }

    func saveArea(_ area: MainWindowArea) { defaults.set(area.rawValue, forKey: Self.key) }
  }

  /// Selected area of the main window. Leaving Profiles with unsaved editor changes asks
  /// first, and no area switch happens while a profile editor mutation is running.
  @MainActor
  final class MainWindowNavigationModel: ObservableObject {
    @Published
    private(set) var selectedArea: MainWindowArea
    @Published
    private(set) var pendingArea: MainWindowArea?
    @Published
    private(set) var discardGeneration = 0
    @Published
    var isDiscardConfirmationPresented = false
    /// Set when `perform(in:_:)` is refused for a running profile editor mutation; the window
    /// shows the reason until dismissed.
    @Published
    var isMutationRefusalPresented = false

    private let persistence: any MainWindowAreaPersistence
    private var profilesEditorIsDirty = false
    private var activeProfilesEditorMutation: RuntimeMutationRequest?
    private var activeProfilesEditorMutationIsRuntimeBound = false
    private var pendingAction: (@MainActor () -> Void)?

    init(persistence: any MainWindowAreaPersistence = UserDefaultsMainWindowAreaPersistence()) {
      self.persistence = persistence
      selectedArea = persistence.loadArea() ?? .status
    }

    /// Asks to show `area`. Returns true when the area is selected on return.
    @discardableResult
    func requestArea(_ area: MainWindowArea) -> Bool {
      guard area != selectedArea else { return true }
      guard activeProfilesEditorMutation == nil else { return false }
      guard profilesEditorIsDirty else {
        selectAcceptedArea(area)
        return true
      }
      pendingAction = nil
      pendingArea = area
      isDiscardConfirmationPresented = true
      return false
    }

    /// Shows `area` and runs `action` there. When the discard question is open the action waits for
    /// the answer: it runs once the area is selected by a discard and is dropped on cancel. It is
    /// refused with a visible message while a profile editor mutation is running.
    @discardableResult
    func perform(in area: MainWindowArea, _ action: @escaping @MainActor () -> Void) -> Bool {
      guard activeProfilesEditorMutation == nil else {
        isMutationRefusalPresented = true
        return false
      }
      if requestArea(area) {
        action()
        return true
      }
      pendingAction = action
      return false
    }

    func setProfilesEditorDirty(_ dirty: Bool) { profilesEditorIsDirty = dirty }

    @discardableResult
    func beginProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == nil else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = false
      cancelPendingArea()
      return true
    }

    /// Runs `body` as a menu-started profile mutation under the editor's mutation tracking.
    /// Returns nil, without running `body`, when the editor holds a mutation.
    func trackMenuProfileMutation<Result>(
      _ request: RuntimeMutationRequest,
      _ body: () async -> Result
    ) async -> Result? {
      guard beginProfilesEditorMutation(request) else { return nil }
      let result = await body()
      finishProfilesEditorMutation(request)
      return result
    }

    func ownsProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      activeProfilesEditorMutation == request
    }

    @discardableResult
    func finishProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == request else { return false }
      activeProfilesEditorMutation = nil
      activeProfilesEditorMutationIsRuntimeBound = false
      return true
    }

    @discardableResult
    func reconcileProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard
        activeProfilesEditorMutation == nil || activeProfilesEditorMutation == request
          || (activeProfilesEditorMutation?.operation == request.operation
            && !activeProfilesEditorMutationIsRuntimeBound)
      else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = true
      cancelPendingArea()
      return true
    }

    func discardPendingArea() {
      guard let pendingArea else {
        cancelPendingArea()
        return
      }
      profilesEditorIsDirty = false
      discardGeneration &+= 1
      self.pendingArea = nil
      isDiscardConfirmationPresented = false
      selectAcceptedArea(pendingArea)
      let action = pendingAction
      pendingAction = nil
      action?()
    }

    func cancelPendingArea() {
      pendingAction = nil
      pendingArea = nil
      isDiscardConfirmationPresented = false
    }

    private func selectAcceptedArea(_ area: MainWindowArea) {
      selectedArea = area
      persistence.saveArea(area)
    }
  }

#endif
