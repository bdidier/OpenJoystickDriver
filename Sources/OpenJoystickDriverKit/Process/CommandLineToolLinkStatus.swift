import Foundation

/// What is at the path of the `ojd` command-line tool link.
///
/// This is the only place the link is classified. The app installs and removes the link and
/// `ojd status` reports it, and both read it through this type, so they agree on what it is.
public struct CommandLineToolLinkStatus: Equatable, Sendable {
  public enum State: String, Codable, CaseIterable, Equatable, Sendable {
    /// A link that points to this app's executable.
    case installed
    /// A link whose target exists but is not this app's executable, such as another app copy.
    case linkedElsewhere
    /// A link whose target does not exist.
    case broken
    /// A file or folder that is not a link; the app never replaces it.
    case blockedByFile
    /// Nothing is at the path.
    case missing
  }

  /// Where the app puts the link.
  public static let defaultPath = "/usr/local/bin/ojd"

  public let state: State
  public let path: String
  /// What the link points at, as stored in the link; nil when the path is not a link.
  public let target: String?

  public init(state: State, path: String, target: String? = nil) {
    self.state = state
    self.path = path
    self.target = target
  }

  /// The executable of the running app, which the link must point to.
  public static var currentExecutable: URL {
    Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
  }

  /// Reads the path without following the link, so a dangling link is `broken`, not `missing`.
  /// A relative target is read from the folder that holds the link.
  public static func probe(
    path: String = defaultPath,
    executable: URL = currentExecutable
  ) -> Self {
    let manager = FileManager.default
    guard let destination = try? manager.destinationOfSymbolicLink(atPath: path) else {
      let present = (try? manager.attributesOfItem(atPath: path)) != nil
      return Self(state: present ? .blockedByFile : .missing, path: path)
    }
    let target = URL(
      fileURLWithPath: destination,
      relativeTo: URL(fileURLWithPath: path).deletingLastPathComponent()
    ).resolvingSymlinksInPath()
    guard manager.fileExists(atPath: target.path) else {
      return Self(state: .broken, path: path, target: destination)
    }
    let ours = target.path == executable.resolvingSymlinksInPath().path
    return Self(state: ours ? .installed : .linkedElsewhere, path: path, target: destination)
  }
}
