import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

extension ControllerOwnershipCommandTests {
  @Test(arguments: ServingFixture.all)
  func theCLIAcceptsAServerChangeExactlyWhenThePolicyOffersTheChoice(_ fixture: ServingFixture) {
    let accepted =
      (try? ControllerOwnershipCommand.checkSupported(
        fixture.device,
        server: fixture.server,
        accessRoute: fixture.accessRoute
      )) != nil
    #expect(accepted == fixture.offersServerChoice, "\(fixture.name)")
  }
}
