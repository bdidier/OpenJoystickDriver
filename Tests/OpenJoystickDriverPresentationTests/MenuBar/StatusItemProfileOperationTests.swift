import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct StatusItemProfileOperationTests {
  @MainActor
  private final class BusyWindow: MenuProfileMutating {
    private(set) var requests: [RuntimeMutationRequest] = []
    var hasSelectedProfile: Bool { false }
    var selectedControllerID: String? { nil }

    func showMainWindow(area: MainWindowArea?) {}
    func showController(id: String) {}
    func showInputTest(controllerID: String) {}
    func importProfile() {}
    func exportProfile() {}
    func installRecordOrMod() {}

    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome? {  // swiftlint:disable:this async_without_await
      requests.append(request)
      return nil
    }
  }

  @Test
  func operationsMapToTheirRuntimeMutation() {
    let id = UUID()
    #expect(
      StatusItemProfileOperation.activate(profileID: id).request.operation
        == .activate(profileID: id)
    )
    #expect(
      StatusItemProfileOperation.deactivate(profileID: id).request.operation
        == .deactivate(profileID: id)
    )
  }

  @Test
  @MainActor
  func operationIsRefusedWithoutSuccessWhileTheEditorHoldsAMutation() async {
    let window = BusyWindow()
    let id = UUID()
    let activated = await StatusItemProfileOperation.activate(profileID: id).perform(on: window)
    let deactivated = await StatusItemProfileOperation.deactivate(profileID: id).perform(on: window)
    #expect(activated == nil)
    #expect(deactivated == nil)
    #expect(window.requests.count == 2)
  }
}
