import Foundation

/// The macOS `DataDirectory`: Application Support, Library/Logs, and the temp locations.
///
/// This type is the only place allowed to build platform paths.
public struct MacOSDataDirectory: DataDirectory {
  public static let directoryName = "OpenJoystickDriver"

  public init() {}

  public func url(for location: DataLocation) -> URL {
    switch location {
    case .applicationData: return library(.applicationSupportDirectory, "Application Support")
    case .cache: return library(.cachesDirectory, "Caches")
    case .logs:
      return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Logs/\(Self.directoryName)",
        isDirectory: true
      )
    case .runtime: return URL(fileURLWithPath: Self.userTemporaryPath(), isDirectory: true)
    case .sharedTemporary: return URL(fileURLWithPath: "/tmp", isDirectory: true)
    case .temporary: return FileManager.default.temporaryDirectory
    case .home: return FileManager.default.homeDirectoryForCurrentUser
    }
  }

  private func library(_ directory: FileManager.SearchPathDirectory, _ fallback: String) -> URL {
    let manager = FileManager.default
    let base =
      manager.urls(for: directory, in: .userDomainMask).first
      ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/\(fallback)")
    return base.appendingPathComponent(Self.directoryName, isDirectory: true)
  }

  /// The per-user temporary folder, which only the user can open.
  private static func userTemporaryPath() -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    let directory =
      length > 0
      ? String(bytes: buffer.prefix(length - 1).map(UInt8.init(bitPattern:)), encoding: .utf8)
      : nil
    return directory ?? NSTemporaryDirectory()
  }
}
