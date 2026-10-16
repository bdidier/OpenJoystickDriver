import Foundation
import OpenJoystickDriverKit

/// The `apiVersion` and `kind` that open every endpoint line, read before the rest of the line.
///
/// A line is refused in this order, each with the supported versions in `details`:
/// no `apiVersion` or no `kind`, or one that is `null` or not a string, is `E1011`; another
/// `apiVersion` is `E1009`; a `kind` that the protocol does not know, or does not accept at this
/// point, is `E1010`. A line that is not a JSON object is `E1003`.
enum EndpointHeader {
  /// The refusal for `data`, or nil when its header is the supported version and one of `accepted`.
  static func refusal(of data: Data, accepting accepted: [String]) -> EndpointError? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return EndpointError(
        code: .invalidMessage,
        message: "The message is not a request: it needs a JSON object."
      )
    }
    guard let apiVersion = object["apiVersion"] as? String, let kind = object["kind"] as? String
    else {
      return EndpointError(
        header: .missingHeader,
        message: "Every line needs both apiVersion and kind, each a string."
      )
    }
    guard apiVersion == OpenJoystickDriverAPI.version else {
      return EndpointError(
        header: .unsupportedEndpointVersion,
        message: "The apiVersion \(apiVersion) is not supported."
      )
    }
    guard accepted.contains(kind) else {
      let expected =
        accepted.isEmpty
        ? "no further request" : accepted.map { "'\($0)'" }.joined(separator: " or ")
      return EndpointError(
        header: .unexpectedKind,
        message: "The kind \(kind) is not accepted here; the service expects \(expected)."
      )
    }
    return nil
  }
}
