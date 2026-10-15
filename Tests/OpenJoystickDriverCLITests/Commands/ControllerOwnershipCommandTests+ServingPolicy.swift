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
        usesRawUSB: fixture.source == .rawUSB
      )) != nil
    #expect(accepted == fixture.offersServerChoice, "\(fixture.name)")
  }
}
