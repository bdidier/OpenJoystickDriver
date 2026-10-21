import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileIssuePresentationTests {
  private static func issue(
    _ kind: ApplicationServiceRemappingProfileIssue.Kind,
    _ code: ErrorCode
  ) -> ApplicationServiceRemappingProfileIssue {
    ApplicationServiceRemappingProfileIssue(id: UUID(), kind: kind, code: code, message: "service")
  }

  @Test
  func aDamagedProfileShowsItsIssueCodeAndText() {
    let codes: [ErrorCode] = [
      .invalidProfile, .unsupportedAPIVersion, .duplicateName, .corruptLibrary,
    ]
    for code in codes {
      let presentation = ProfileIssuePresentation(Self.issue(.damagedProfile, code))
      #expect(presentation.code == code.rawValue)
      #expect(presentation.title == OJDLocalized.string("profiles.damagedProfile"))
      #expect(presentation.message == OJDLocalized.string("profiles.damagedProfileMessage"))
      #expect(presentation.titleWithCode.contains(code.rawValue))
      #expect(presentation.accessibilityValue.contains(code.rawValue))
    }
  }

  @Test
  func anUnusableLibraryShowsItsIssueCodeAndText() {
    let presentation = ProfileIssuePresentation(Self.issue(.unusableLibrary, .corruptLibrary))
    #expect(presentation.code == ErrorCode.corruptLibrary.rawValue)
    #expect(presentation.title == OJDLocalized.string("profiles.damagedLibrary"))
    #expect(presentation.message == OJDLocalized.string("profiles.damagedSelectionsMessage"))
  }
}
