import Foundation
import OpenJoystickDriverKit

/// What the Profiles screen shows for one damaged profile or unusable active-profile list: the
/// title and text of its kind and the error code of the profile issue, the same code
/// `ojd profile list --json` prints.
struct ProfileIssuePresentation: Equatable {
  let title: String
  let message: String
  let code: String

  init(_ issue: ApplicationServiceRemappingProfileIssue) {
    switch issue.kind {
    case .damagedProfile:
      title = OJDLocalized.string("profiles.damagedProfile")
      message = OJDLocalized.string("profiles.damagedProfileMessage")
    case .unusableLibrary:
      title = OJDLocalized.string("profiles.damagedLibrary")
      message = OJDLocalized.string("profiles.damagedSelectionsMessage")
    }
    code = issue.code.rawValue
  }

  /// The title with the code, as the detail's section header reads it.
  var titleWithCode: String { OJDLocalized.formatted("error.withCode", title, code) }

  /// What VoiceOver reads after the title: the text and the code.
  var accessibilityValue: String { OJDLocalized.formatted("error.withCode", message, code) }
}
