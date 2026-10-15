import Foundation

/// A `DataDirectory` that places every location under one caller-chosen root.
///
/// Tests and embedders use it to keep stores inside a directory they own.
public struct RootedDataDirectory: DataDirectory {
  public let root: URL

  public init(root: URL) { self.root = root }

  public func url(for location: DataLocation) -> URL {
    root.appendingPathComponent(location.rawValue, isDirectory: true)
  }
}
