import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct RemappingForegroundPolicyTests {
  @Test
  func applicationScopeRequiresExactFrontmostAppID() {
    let scope = RemappingApplicationScope.application(appID: "com.example.Game")
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: scope,
        frontmostAppID: "com.example.Game",
        accessState: .granted,
        outputSuppressed: false
      ) == .eligible
    )
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: scope,
        frontmostAppID: "com.example.Game.Helper",
        accessState: .granted,
        outputSuppressed: false
      ) == .targetApplicationNotFrontmost
    )
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: scope,
        frontmostAppID: nil,
        accessState: .granted,
        outputSuppressed: false
      ) == .targetApplicationNotFrontmost
    )
  }

  @Test
  func globalScopeStillRequiresPostEventAuthorization() {
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: .global,
        frontmostAppID: nil,
        accessState: .granted,
        outputSuppressed: false
      ) == .eligible
    )
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: .global,
        frontmostAppID: nil,
        accessState: .notAuthorized,
        outputSuppressed: false
      ) == .postEventAccessNotAuthorized
    )
  }

  @Test
  func explicitSuppressionPrecedesOtherEligibilityStates() {
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: .application(appID: "com.example.Game"),
        frontmostAppID: nil,
        accessState: .notAuthorized,
        outputSuppressed: true
      ) == .outputSuppressed
    )
  }
}
