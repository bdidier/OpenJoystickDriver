import Foundation
import OpenJoystickDriverKit

/// What Explain Error Code shows for typed text. The lookup is the one `ojd explain` does: the
/// text, upper-cased, names an ``ErrorCode``, and its localized explanation is the answer.
enum ErrorCodeExplanation: Equatable {
  case explained(code: String, explanation: String)
  case unknown(String)

  /// The answer for `text`, or nil while the text is blank.
  static func lookup(_ text: String) -> Self? {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else { return nil }
    guard let code = ErrorCode(typed: typed) else { return .unknown(typed) }
    return .explained(code: code.rawValue, explanation: code.localizedExplanation)
  }
}
