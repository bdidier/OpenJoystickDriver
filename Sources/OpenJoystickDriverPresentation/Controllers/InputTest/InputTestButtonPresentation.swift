#if canImport(SwiftUI)

  import OpenJoystickDriverKit

  enum InputTestButtonPresentation {
    /// Controls the live input view draws in its own clusters.
    static let drawnControls: Set<Control> = [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder,
      .leftTrigger, .rightTrigger, .back, .start, .guide, .leftStickClick, .rightStickClick,
    ]

    /// The core face, shoulder, stick and system set; Share, Capture, Mute, touchpad and paddles
    /// surface as extras in Developer Tools.
    static let coreDiagnosticControls = drawnControls

    /// Pressed controls no cluster draws, such as Share and Capture, in `Control` order.
    static func additionalControls(in state: ControllerState) -> [Control] {
      Control.allCases.filter { state.pressed.contains($0) && !drawnControls.contains($0) }
    }

    /// The remapping source name of `control`.
    static func localizedTitle(for control: Control) -> String {
      RuntimePresentation.sourceLabel(.button(control))
    }
  }

#endif
