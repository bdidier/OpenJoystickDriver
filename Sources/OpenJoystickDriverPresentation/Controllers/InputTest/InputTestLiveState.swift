#if canImport(SwiftUI)

  import Combine
  import OpenJoystickDriverKit

  /// High-frequency input state is isolated from the lower-frequency session and output model so
  /// controller reports do not invalidate the complete Input Test window at the polling rate.
  @MainActor
  final class InputTestLiveState: ObservableObject {
    @Published
    private(set) var snapshot: ControllerState

    init(snapshot: ControllerState = .neutral) {
      self.snapshot = snapshot
    }

    func reset() {
      update(.neutral)
    }

    func update(_ nextSnapshot: ControllerState) {
      guard snapshot != nextSnapshot else { return }
      snapshot = nextSnapshot
    }
  }

#endif
