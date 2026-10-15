import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct RuntimeExtraButtonTests {
  @Test(arguments: [
    Control.auxiliary1, .auxiliary2, .leftPaddle1, .rightPaddle1, .auxiliary3, .auxiliary4,
    .auxiliary5, .auxiliary6, .leftPaddle2, .rightPaddle2, .leftTrackpadClick, .rightTrackpadClick,
  ])
  func captureAndAuthoringExposeInputOnlyButtons(button: Control) {
    var state = ControllerState.neutral
    state.pressed = [button]
    #expect(RuntimePresentation.detectedSource(from: state) == .button(button))
    #expect(SourceOption.options().contains { $0.source == .button(button) })
    let destinations = DestinationOption.options(
      for: .button(button),
      including: .gamepadButton(button)
    )
    #expect(!destinations.contains { $0.destination == .gamepadButton(button) })
    #expect(destinations.contains { $0.destination == .keyboard(key: .space, modifiers: []) })
  }
}
