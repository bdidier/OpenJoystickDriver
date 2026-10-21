import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowNavigationTests {
  @Test
  @MainActor
  func dockVisibilityTracksPrimaryWindowsAndRetriesFailedPolicyChanges() {
    var requestedPolicies: [NSApplication.ActivationPolicy] = []
    var shouldSucceed = true
    let visibility = PrimaryWindowVisibilityController { policy in
      requestedPolicies.append(policy)
      return shouldSucceed
    }

    #expect(visibility.appliedPolicy == .accessory)
    visibility.opened(.workbench)
    #expect(requestedPolicies == [.regular])
    #expect(visibility.appliedPolicy == .regular)

    visibility.opened(.inputTest)
    visibility.closed(.workbench)
    #expect(requestedPolicies == [.regular])
    #expect(visibility.isOpen(.inputTest))

    shouldSucceed = false
    visibility.closed(.inputTest)
    #expect(requestedPolicies == [.regular, .accessory])
    #expect(visibility.appliedPolicy == .regular)

    shouldSucceed = true
    visibility.opened(.inputTest)
    visibility.closed(.inputTest)
    #expect(requestedPolicies == [.regular, .accessory, .accessory])
    #expect(visibility.appliedPolicy == .accessory)

    visibility.keepsDockIcon = true
    #expect(visibility.appliedPolicy == .regular)
    visibility.opened(.settings)
    visibility.closed(.settings)
    #expect(visibility.appliedPolicy == .regular)
    visibility.keepsDockIcon = false
    #expect(visibility.appliedPolicy == .accessory)
  }

  @Test
  @MainActor
  func menuProfileMutationIsRefusedWhileTheEditorHoldsOneAndRunsOnceReleased() async {
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(
        defaults: UserDefaults(suiteName: "MainWindowNavigationTests.\(UUID().uuidString)")!
      )
    )
    let editorRequest = RuntimeMutationRequest(operation: .create(profileID: UUID()))
    #expect(navigation.beginProfilesEditorMutation(editorRequest))

    var runs = 0
    let menuRequest = RuntimeMutationRequest(operation: .activate(profileID: UUID()))
    let refused: Int? = await navigation.trackMenuProfileMutation(menuRequest) {
      runs += 1
      return runs
    }
    #expect(refused == nil)
    #expect(runs == 0)

    navigation.finishProfilesEditorMutation(editorRequest)
    let ran: Int? = await navigation.trackMenuProfileMutation(menuRequest) {
      runs += 1
      return runs
    }
    #expect(ran == 1)
    #expect(!navigation.ownsProfilesEditorMutation(menuRequest))
  }

  @MainActor
  private static func dirtyNavigation() -> MainWindowNavigationModel {
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(
        defaults: UserDefaults(suiteName: "MainWindowNavigationTests.\(UUID().uuidString)")!
      )
    )
    navigation.requestArea(.profiles)
    navigation.setProfilesEditorDirty(true)
    return navigation
  }

  @Test
  @MainActor
  func actionWaitsForTheDiscardAnswerAndRunsAfterDiscard() {
    let navigation = Self.dirtyNavigation()
    var runs = 0
    #expect(!navigation.perform(in: .library) { runs += 1 })
    #expect(runs == 0)
    #expect(navigation.isDiscardConfirmationPresented)
    navigation.discardPendingArea()
    #expect(navigation.selectedArea == .library)
    #expect(runs == 1)
  }

  @Test
  @MainActor
  func actionIsDroppedWhenTheDiscardIsCancelled() {
    let navigation = Self.dirtyNavigation()
    var runs = 0
    navigation.perform(in: .library) { runs += 1 }
    navigation.cancelPendingArea()
    navigation.requestArea(.library)
    navigation.cancelPendingArea()
    navigation.discardPendingArea()
    #expect(runs == 0)
  }

  @Test
  @MainActor
  func actionRunsAtOnceInTheSelectedAreaAndIsRefusedDuringAMutation() {
    let navigation = Self.dirtyNavigation()
    var runs = 0
    #expect(navigation.perform(in: .profiles) { runs += 1 })
    #expect(runs == 1)
    let request = RuntimeMutationRequest(operation: .create(profileID: UUID()))
    #expect(navigation.beginProfilesEditorMutation(request))
    #expect(!navigation.perform(in: .profiles) { runs += 1 })
    #expect(runs == 1)
    #expect(navigation.isMutationRefusalPresented)
  }

  @Test
  func mainWindowUsesStableContentSizingAcrossAreas() {
    #expect(MainWindowSizingPolicy.defaultContentSize == NSSize(width: 1_040, height: 700))
    #expect(MainWindowSizingPolicy.minimumContentSize == NSSize(width: 960, height: 560))
  }

  @Test
  func restoredAndLiveResizeFramesCannotCrossTheContentMinimum() {
    let minimum = NSSize(width: 816, height: 604)
    let restored = WindowFramePolicy.fittingFrame(
      NSRect(x: 200, y: 300, width: 640, height: 420),
      minimumSize: minimum
    )
    #expect(restored == NSRect(x: 200, y: 116, width: 816, height: 604))
    #expect(
      WindowFramePolicy.fittingSize(NSSize(width: 700, height: 500), minimumSize: minimum)
        == minimum
    )
    #expect(
      WindowFramePolicy.fittingSize(NSSize(width: 1_100, height: 760), minimumSize: minimum)
        == NSSize(width: 1_100, height: 760)
    )
  }

  @Test
  @MainActor
  func frameMinimumConvertsBackToTheRequiredContentMinimum() {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: MainWindowSizingPolicy.defaultContentSize),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.toolbar = NSToolbar(identifier: "SizingPolicyTest")
    let minimumFrameSize = MainWindowSizingPolicy.minimumFrameSize(for: window)
    let convertedContentSize = window.contentRect(
      forFrameRect: NSRect(origin: .zero, size: minimumFrameSize)
    ).size

    #expect(convertedContentSize == MainWindowSizingPolicy.minimumContentSize)
  }

  @Test
  func restoredWindowFramesAreClampedToTheUsableScreen() {
    let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    #expect(
      WindowFramePolicy.clampedFrame(NSRect(x: 1_300, y: -100, width: 900, height: 620), to: screen)
        == NSRect(x: 540, y: 0, width: 900, height: 620)
    )
    #expect(
      WindowFramePolicy.clampedFrame(
        NSRect(x: 1_300, y: 700, width: 500, height: 300),
        to: screen,
        minimumSize: NSSize(width: 816, height: 604)
      ) == NSRect(x: 624, y: 296, width: 816, height: 604)
    )
  }

  @Test
  @MainActor
  func restoresTheLastAcceptedArea() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let initial = MainWindowNavigationModel(persistence: persistence)
    #expect(initial.selectedArea == .controllers)
    initial.requestArea(.profiles)
    #expect(initial.selectedArea == .profiles)

    let restored = MainWindowNavigationModel(persistence: persistence)
    #expect(restored.selectedArea == .profiles)
  }

  @Test
  @MainActor
  func dirtySelectionPersistsOnlyAfterDiscard() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let navigation = MainWindowNavigationModel(persistence: persistence)
    navigation.requestArea(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestArea(.library)

    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == .library)
    #expect(navigation.isDiscardConfirmationPresented)
    let beforeDiscard = MainWindowNavigationModel(persistence: persistence)
    #expect(beforeDiscard.selectedArea == .controllers)

    navigation.discardPendingArea()
    #expect(navigation.selectedArea == .library)
    #expect(navigation.pendingArea == nil)
    #expect(!navigation.isDiscardConfirmationPresented)
    let afterDiscard = MainWindowNavigationModel(persistence: persistence)
    #expect(afterDiscard.selectedArea == .library)
  }

  @Test
  @MainActor
  func canceledDirtySelectionLeavesThePersistedAreaUnchanged() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let navigation = MainWindowNavigationModel(persistence: persistence)
    navigation.requestArea(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestArea(.activity)
    navigation.cancelPendingArea()

    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)
    let restored = MainWindowNavigationModel(persistence: persistence)
    #expect(restored.selectedArea == .controllers)
  }

  @Test
  @MainActor
  func activeProfileMutationKeepsTheProfilesAreaMountedUntilResolution() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsMainWindowAreaPersistence(defaults: defaults)

    let navigation = MainWindowNavigationModel(persistence: persistence)
    let request = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    navigation.requestArea(.profiles)
    navigation.setProfilesEditorDirty(true)
    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(false)

    navigation.requestArea(.library)

    #expect(navigation.selectedArea == .profiles)
    #expect(navigation.pendingArea == nil)
    #expect(!navigation.isDiscardConfirmationPresented)

    #expect(navigation.finishProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(true)
    navigation.requestArea(.library)

    #expect(navigation.pendingArea == .library)
    #expect(navigation.isDiscardConfirmationPresented)

    navigation.cancelPendingArea()
    navigation.setProfilesEditorDirty(false)
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .library)
  }

  @Test
  @MainActor
  func overlappingProfileMutationCannotReleaseTheFirstNavigationOwner() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )
    let first = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    let second = RuntimeMutationRequest(operation: .importProfile(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(second))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)

    #expect(!navigation.finishProfilesEditorMutation(second))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)

    #expect(navigation.finishProfilesEditorMutation(first))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .library)
  }

  @Test
  @MainActor
  func matchingPreflightFailureReleasesNavigationOwner() {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )
    let request = RuntimeMutationRequest(operation: .update(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == nil)

    #expect(
      !navigation.finishProfilesEditorMutation(RuntimeMutationRequest(operation: request.operation))
    )
    #expect(navigation.ownsProfilesEditorMutation(request))
    #expect(navigation.finishProfilesEditorMutation(request))

    navigation.setProfilesEditorDirty(false)
    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .library)
  }

  @Test
  @MainActor
  func preflightFailureReleasesBothOwnersAndPreservesDirtyDraft() async {
    let suiteName = "MainWindowNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let original = makeProfile(name: "Original")
    let invalid = makeProfile(id: original.id, name: "")
    let request = RuntimeMutationRequest(operation: .update(profileID: original.id))
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let library = ProfileLibraryModel(runtime: RuntimeViewModel(gateway: gateway))
    var transition = ProfileEditorTransitionState()
    let navigation = MainWindowNavigationModel(
      persistence: UserDefaultsMainWindowAreaPersistence(defaults: defaults)
    )

    transition.setDirty(true)
    #expect(transition.beginMutation(request) == .acquired)
    #expect(navigation.beginProfilesEditorMutation(request))

    let result = await library.updateRemappingProfile(
      invalid,
      expectedCurrent: original,
      request: request
    )
    #expect(result.request == request)
    #expect(transition.finishMutationIfOwned(result.request, succeeded: false).didRelease)
    #expect(navigation.finishProfilesEditorMutation(result.request))
    navigation.setProfilesEditorDirty(transition.isDirty)

    navigation.requestArea(.library)
    #expect(navigation.selectedArea == .controllers)
    #expect(navigation.pendingArea == .library)
    #expect(navigation.isDiscardConfirmationPresented)
    #expect(transition.isDirty)
  }
}
