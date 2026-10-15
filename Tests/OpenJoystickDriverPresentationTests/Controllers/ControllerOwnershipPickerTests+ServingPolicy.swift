import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

extension ControllerOwnershipPickerTests {
  @Test(arguments: ServingFixture.all)
  func theGUIShowsThePickerExactlyWhenThePolicyOffersTheChoice(_ fixture: ServingFixture) {
    #expect(
      ControllerOwnershipPicker.isShown(for: fixture.device) == fixture.offersServerChoice,
      "\(fixture.name)"
    )
  }
}
