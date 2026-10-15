import Foundation

/// The `apiVersion` of every JSON document and line that `ojd --json` prints, that the endpoint
/// speaks, and that OJD reads or writes as a file.
public enum OpenJoystickDriverAPI {
  public static let version = "openjoystickdriver/v1alpha1"

  /// Why a document with this `apiVersion` and `kind` is not a supported `expected`, or nil when
  /// it is.
  ///
  /// OJD does not upgrade a document of another version: the problem names what it found and what
  /// it supports. A missing or unknown `apiVersion` carries ``ErrorCode/unsupportedAPIVersion``;
  /// a wrong `kind` carries no code.
  public static func headerProblem(
    apiVersion: Any?,
    kind: Any?,
    expected: String
  ) -> DocumentHeaderProblem? {
    guard let apiVersion else {
      return DocumentHeaderProblem(
        code: .unsupportedAPIVersion,
        "no apiVersion found; the supported apiVersion is \(version)"
      )
    }
    guard (apiVersion as? String) == version else {
      return DocumentHeaderProblem(
        code: .unsupportedAPIVersion,
        "apiVersion \(apiVersion) is not supported; the supported apiVersion is \(version)"
      )
    }
    guard let kind else {
      return DocumentHeaderProblem(code: nil, "no kind found; expected \(expected)")
    }
    guard (kind as? String) == expected else {
      return DocumentHeaderProblem(code: nil, "expected \(expected), found \(kind)")
    }
    return nil
  }

  /// Requires `document` to carry the supported `apiVersion` and the `kind` it is read as. A
  /// `file` name leads the reason.
  static func requireHeader(
    _ document: [String: Any],
    kind: String,
    file: String? = nil
  ) throws {
    guard
      let problem = headerProblem(
        apiVersion: document["apiVersion"],
        kind: document["kind"],
        expected: kind
      )
    else { return }
    throw file.map { problem.located(in: $0) } ?? problem
  }
}

/// Why a document's `apiVersion` or `kind` is not the supported one.
///
/// `code` is ``ErrorCode/unsupportedAPIVersion`` when the `apiVersion` is missing or unknown, and
/// nil when only the `kind` is wrong. `message` names the file when there is one, the version
/// found, and the supported one. `description` leads with the code, as ``ModPackageError`` does.
public struct DocumentHeaderProblem: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  public let code: ErrorCode?
  public let message: String

  init(code: ErrorCode?, _ message: String) {
    self.code = code
    self.message = message
  }

  /// The same problem, with `file` leading the message.
  func located(in file: String) -> Self { Self(code: code, "\(file): \(message)") }

  public var description: String { (code.map { "\($0.rawValue): " } ?? "") + message }
  public var errorDescription: String? { description }
}
