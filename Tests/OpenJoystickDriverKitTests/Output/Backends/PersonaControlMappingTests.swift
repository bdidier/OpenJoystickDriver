import Testing

@testable import OpenJoystickDriverKit

/// Which controls each virtual persona carries, and the reason each missing one is missing.
struct PersonaControlMappingTests {
  private typealias Dispatcher = UserSpaceOutputDispatcher

  private static let steamControllerWired = LogicalControllerID(vendorID: 0x28DE, productID: 0x1102)
  private static let steamDeck = LogicalControllerID(vendorID: 0x28DE, productID: 0x1205)
  private static let steamTriton = LogicalControllerID(vendorID: 0x28DE, productID: 0x1303)

  private static let uncarried: [Control] = [
    .touchpadClick, .microphone, .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2,
    .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7,
    .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick, .leftTrackpadTouch,
    .rightTrackpadTouch, .rightTrackpadClick,
  ]

  @Test
  func theClassicSteamControllerRightPadIsItsRightStick() {
    #expect(Dispatcher.rightPadIsRightStick(Self.steamControllerWired))
    let pad = Dispatcher.virtualControl(.rightTrackpadClick, rightPadIsRightStick: true)
    #expect(Dispatcher.buttonBit(for: pad) == 7)
  }

  @Test
  func aDeckAndATritonKeepTheirRealRightStickClick() {
    for identifier in [Self.steamDeck, Self.steamTriton] {
      #expect(!Dispatcher.rightPadIsRightStick(identifier))
      let pad = Dispatcher.virtualControl(.rightTrackpadClick, rightPadIsRightStick: false)
      #expect(Dispatcher.buttonBit(for: pad) == nil)
      let stick = Dispatcher.virtualControl(.rightStickClick, rightPadIsRightStick: false)
      #expect(Dispatcher.buttonBit(for: stick) == 7)
    }
  }

  @Test
  func reportMappingAppliesTheRightPadRule() {
    let input = ControllerState(pressed: [.rightTrackpadClick])
    func buttons(rightPadIsRightStick: Bool) -> UInt32 {
      var state = VirtualGamepadState()
      Dispatcher.apply(
        input,
        labels: .standard,
        stickTransfer: Dispatcher.StickTransfer(deadzone: 0, rescalesDeadzone: false),
        rightPadIsRightStick: rightPadIsRightStick,
        to: &state
      )
      return state.buttons
    }
    #expect(buttons(rightPadIsRightStick: true) == 1 << 7)
    #expect(buttons(rightPadIsRightStick: false) == 0)
  }

  @Test(arguments: [VirtualHIDProfileID.generic, .sdlCompatible])
  func noPersonaCarriesAnUncarriedControl(_ id: VirtualHIDProfileID) throws {
    let profile = try id.makeProfile()
    let neutral = profile.inputReport(for: .neutral)
    for control in Self.uncarried {
      #expect(Dispatcher.buttonBit(for: control) == nil)
      #expect(profile.inputReport(for: ControllerState(pressed: [control])) == neutral)
    }
  }

  @Test
  func captureIsCarriedByTheGenericPersonaOnly() throws {
    let capture = ControllerState(pressed: [.capture])
    let generic = try VirtualHIDProfileID.generic.makeProfile()
    #expect(generic.inputReport(for: capture) != generic.inputReport(for: .neutral))
    let sdl = try VirtualHIDProfileID.sdlCompatible.makeProfile()
    #expect(sdl.inputReport(for: capture) == sdl.inputReport(for: .neutral))
  }
}
