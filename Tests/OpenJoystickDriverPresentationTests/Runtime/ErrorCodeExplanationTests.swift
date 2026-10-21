import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ErrorCodeExplanationTests {
  @Test
  func aCodeMapsToTheExplanationOjdExplainPrints() throws {
    let code = try #require(ErrorCode(rawValue: "E3029"))
    #expect(
      ErrorCodeExplanation.lookup("E3029")
        == .explained(code: "E3029", explanation: code.localizedExplanation)
    )
  }

  @Test
  func theCaseAndSurroundingSpaceOfTheCodeDoNotMatter() {
    #expect(ErrorCodeExplanation.lookup("  e3029\n") == ErrorCodeExplanation.lookup("E3029"))
  }

  @Test
  func textThatIsNoCodeIsUnknown() {
    #expect(ErrorCodeExplanation.lookup("E0000") == .unknown("E0000"))
  }

  @Test
  func blankTextLooksNothingUp() { #expect(ErrorCodeExplanation.lookup(" ") == nil) }
}
