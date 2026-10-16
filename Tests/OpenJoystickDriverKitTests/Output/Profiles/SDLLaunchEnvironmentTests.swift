import Testing

@testable import OpenJoystickDriverKit

struct SDLLaunchEnvironmentTests {
  @Test
  func setsTheMappingLineOfEachProfileOnceInProfileOrder() throws {
    let environment = try SDLLaunchEnvironment.environment(
      adding: [.sdlCompatible, .generic, .generic],
      to: ["PATH": "/usr/bin"]
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
      to: [SDLLaunchEnvironment.variable: "abc,Mine,a:b0\n"]
    )
    let generic = try VirtualHIDProfileID.generic.gamepadMapping().sdlMapping
    #expect(environment[SDLLaunchEnvironment.variable] == "abc,Mine,a:b0\n" + generic)
  }

  @Test
  func failsWithoutAProfile() {
    #expect(throws: SDLLaunchEnvironment.Failure.noProfile) {
      try SDLLaunchEnvironment.environment(adding: [], to: [SDLLaunchEnvironment.variable: "x"])
    }
  }
}
