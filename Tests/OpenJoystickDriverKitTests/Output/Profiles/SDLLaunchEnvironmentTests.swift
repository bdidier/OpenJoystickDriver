import Testing

@testable import OpenJoystickDriverKit

struct SDLLaunchEnvironmentTests {
  @Test
  func setsTheMappingLineOfEachProfileOnceInProfileOrder() throws {
    let environment = try SDLLaunchEnvironment.environment(
      adding: [.sdlCompatible, .generic, .generic],
      to: ["PATH": "/usr/bin"],
      gameControllerBackend: false
    )
    let lines = try VirtualHIDProfileID.allCases.filter { [.sdlCompatible, .generic].contains($0) }
      .map { try $0.gamepadMapping().sdlMapping }
    #expect(lines.count == 2)
    #expect(environment[SDLLaunchEnvironment.variable] == lines.joined(separator: "\n"))
    #expect(environment["PATH"] == "/usr/bin")
  }

  @Test
  func keepsAValueThatIsAlreadySetFirst() throws {
    let environment = try SDLLaunchEnvironment.environment(
      adding: [.generic],
      to: [SDLLaunchEnvironment.variable: "abc,Mine,a:b0\n"],
      gameControllerBackend: false
    )
    let generic = try VirtualHIDProfileID.generic.gamepadMapping().sdlMapping
    #expect(environment[SDLLaunchEnvironment.variable] == "abc,Mine,a:b0\n" + generic)
  }

  @Test
  func failsWithoutAProfile() {
    #expect(throws: SDLLaunchEnvironment.Failure.noProfile) {
      try SDLLaunchEnvironment.environment(
        adding: [],
        to: [SDLLaunchEnvironment.variable: "x"],
        gameControllerBackend: false
      )
    }
  }

  @Test
  func theGameControllerBackendSetsExactlyItsHintsAndReplacesSetValues() throws {
    let environment = try SDLLaunchEnvironment.environment(
      adding: [.generic],
      to: ["PATH": "/usr/bin", "SDL_JOYSTICK_HIDAPI": "1", "SDL_JOYSTICK_HIDAPI_XBOX": "1"],
      gameControllerBackend: true
    )
    #expect(
      SDLLaunchEnvironment.gameControllerBackend == [
        "SDL_JOYSTICK_MFI": "1",
        "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1",
        "SDL_JOYSTICK_IOKIT": "0",
        "SDL_JOYSTICK_HIDAPI": "0",
      ]
    )
    var expected = SDLLaunchEnvironment.gameControllerBackend
    expected["PATH"] = "/usr/bin"
    expected["SDL_JOYSTICK_HIDAPI_XBOX"] = "1"
    expected[SDLLaunchEnvironment.variable] = try VirtualHIDProfileID.generic.gamepadMapping()
      .sdlMapping
    #expect(environment == expected)
  }
}
