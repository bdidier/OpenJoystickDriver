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

    /// The symbol of one D-pad direction: a triangle pointing that way, so no two directions
    /// share a glyph.
    static func dpadSymbol(_ direction: RemappingDpadDirection) -> String {
      switch direction {
      case .up: "arrowtriangle.up.fill"
      case .down: "arrowtriangle.down.fill"
      case .left: "arrowtriangle.left.fill"
      case .right: "arrowtriangle.right.fill"
      }
    }

    /// The remapping source name of `control`.
    static func localizedTitle(for control: Control) -> String {
      RuntimePresentation.sourceLabel(.button(control))
    }
  }

#endif
