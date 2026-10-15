import Foundation

/// What is at the path of the `ojd` command-line tool link.
///
/// The app installs and removes the link; this type only reports on it, so `ojd status` and the
/// app agree on what the link is.
public struct CommandLineToolLinkStatus: Equatable, Sendable {
  public enum State: String, Codable, Equatable, Sendable {
    /// A link whose target exists.
    case installed
    /// Nothing is at the path.
    case missing
    /// A link whose target does not exist, or a file that is not a link.
    case broken
  }

  /// Where the app puts the link.
  public static let defaultPath = "/usr/local/bin/ojd"

  public let state: State
  public let path: String
  /// What the link points at; nil when nothing is at the path or it is not a link.
  public let target: String?

  public init(state: State, path: String, target: String? = nil) {
    self.state = state
    self.path = path
    self.target = target
  }

  /// Reads the path without following the link, so a dangling link is `broken`, not `missing`.
  public static func probe(path: String = defaultPath) -> Self {
    let manager = FileManager.default
    guard let destination = try? manager.destinationOfSymbolicLink(atPath: path) else {
      let present = (try? manager.attributesOfItem(atPath: path)) != nil
      return Self(state: present ? .broken : .missing, path: path)
    }
    let resolved = URL(
      fileURLWithPath: destination,
      relativeTo: URL(fileURLWithPath: path).deletingLastPathComponent()
    )
    let exists = manager.fileExists(atPath: resolved.path)
    return Self(state: exists ? .installed : .broken, path: path, target: destination)
  }
}
