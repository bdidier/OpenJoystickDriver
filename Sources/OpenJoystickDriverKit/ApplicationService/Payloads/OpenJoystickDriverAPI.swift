/// The `apiVersion` of every JSON document and line that `ojd --json` prints, that the endpoint
/// speaks, and that OJD reads or writes as a file.
public enum OpenJoystickDriverAPI {
  public static let version = "openjoystickdriver/v1alpha1"

  /// Why a document with this `apiVersion` and `kind` is not a supported `expected`, or nil when
  /// it is.
  ///
  /// OJD does not upgrade a document of another version: the reason names what it found and what
  /// it supports.
  public static func headerProblem(apiVersion: Any?, kind: Any?, expected: String) -> String? {
    guard let apiVersion else {
      return "no apiVersion found; the supported apiVersion is \(version)"
    }
    guard (apiVersion as? String) == version else {
      return "apiVersion \(apiVersion) is not supported; the supported apiVersion is \(version)"
    }
    guard let kind else { return "no kind found; expected \(expected)" }
    guard (kind as? String) == expected else { return "expected \(expected), found \(kind)" }
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
    throw ControllerRecordProblem(file.map { "\($0): \(problem)" } ?? problem)
  }
}
