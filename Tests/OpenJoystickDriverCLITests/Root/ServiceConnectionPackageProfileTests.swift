import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct ServiceConnectionPackageProfileTests {
  @Test
  func aReadOnlyPackageProfileShowsTheLocalizedExplanationWithItsCode() {
    let error = ApplicationServiceRemappingRPCError(
      code: .packageProfileReadOnly,
      message: "A package profile cannot be changed."
    )

    let failure = ServiceConnection.failure(for: error) as? CLIFailure

    #expect(failure?.id == .packageProfileReadOnly)
    #expect(failure?.id.rawValue == "E3029")
    #expect(failure?.message == Localization().string("error.E3029"))
    #expect(failure?.message.contains(error.message) == false)
  }
}
