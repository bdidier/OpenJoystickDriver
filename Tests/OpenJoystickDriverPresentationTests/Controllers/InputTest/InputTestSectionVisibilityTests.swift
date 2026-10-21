import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

extension InputTestTests {
  @Test
  @MainActor
  func motionAndLightingAreHiddenWithoutTheirCapability() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    #expect(model.visibleSections == [.liveInput, .rumble])
  }

  @Test
  @MainActor
  func motionShowsWithAGyroscopeAndLightingWithALightingFeature() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(
      makeInputTestDevice(
        capabilities: PhysicalControllerOutputCapabilities(
          rumbleMotors: [.lowFrequency],
          lightingFeatures: [.programmableColor]
        ),
        hasMotion: true
      )
    )
    #expect(model.visibleSections == [.liveInput, .motion, .rumble, .lighting])
  }
}
