import Foundation

public enum SettingsStoreError: Error, Equatable, LocalizedError, Sendable {
  /// The file is not valid JSON of the `Settings` kind (including an unknown key).
  case damaged(file: String)
  /// The file's `apiVersion` or `kind` is not the supported one; the problem names the file.
  case unsupported(DocumentHeaderProblem)
  case unwritable(file: String)

  public var errorDescription: String? {
    switch self {
    case .damaged(let file):
      "The settings file \(file) is damaged. Fix or delete it, then try again."
    case .unsupported(let problem):
      problem.description + " Delete the file or rewrite it for the supported apiVersion."
    case .unwritable(let file): "The settings file \(file) cannot be written."
    }
  }
}

/// Reads and writes the `Settings.json` file through the `DataDirectory` port.
///
/// The layers, lowest to highest precedence:
/// 1. the built-in defaults (``ApplicationSettingKey/defaultValue``);
/// 2. the user file in ``DataLocation/applicationData``, which is the only file OJD writes.
///
/// A missing file is an empty layer. A damaged or unsupported file is an error, never an empty
/// layer, so a mistake does not silently reset settings. An update holds an advisory lock on a
/// sidecar file while it reads, changes, and writes, so the app, the service, and the CLI cannot
/// lose each other's updates.
public struct SettingsStore: Sendable {
  public static let fileName = "Settings.json"
  /// The sidecar file whose advisory lock serializes updates.
  public static let lockFileName = "Settings.json.lock"
  /// The location whose `Settings.json` is read and written.
  public static let location = DataLocation.applicationData

  private let directory: any DataDirectory

  public init(directory: any DataDirectory = MacOSDataDirectory()) { self.directory = directory }

  /// The path of the user file.
  public var userFileURL: URL { directory.fileURL(Self.fileName, in: Self.location) }

  /// The folder that holds the user file.
  public var folderURL: URL { directory.url(for: Self.location) }

  /// The built-in defaults overlaid by the user file.
  public func load() throws -> SettingsDocument {
    try SettingsDocument().overlaid(by: read(userFileURL))
  }

  /// The value of `key` after the user file and the built-in default apply.
  ///
  /// For `launchAtLogin` this is the stored opt-out, not the login item; macOS answers for the
  /// login item (see ``ApplicationServiceManager/isLaunchAtLoginEnabled``).
  public func value(of key: ApplicationSettingKey) throws -> Bool {
    try load()[key] ?? key.defaultValue
  }

  /// Whether the user turned launch at login off, so the app must not register itself again.
  public func launchAtLoginOptOut() throws -> Bool { try load().launchAtLoginOptOut ?? false }

  /// Stores `value` for `key` in the user file.
  public func set(_ key: ApplicationSettingKey, to value: Bool) throws {
    try update([key: value])
  }

  /// Stores every value in `values` in the user file in one write.
  public func update(_ values: [ApplicationSettingKey: Bool]) throws {
    let url = userFileURL
    let folder = folderURL
    do {
      try FileManager.default.createDirectory(
        at: folder,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch { throw SettingsStoreError.unwritable(file: url.path) }
    let lock = open(
      folder.appendingPathComponent(Self.lockFileName).path,
      O_CREAT | O_RDWR | O_CLOEXEC,
      0o600
    )
    guard lock >= 0 else { throw SettingsStoreError.unwritable(file: url.path) }
    // Closing the descriptor also releases the lock.
    defer { close(lock) }
    while flock(lock, LOCK_EX) != 0 {
      guard errno == EINTR else { throw SettingsStoreError.unwritable(file: url.path) }
    }
    var document = try read(url)
    for (key, value) in values { document[key] = value }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do { try encoder.encode(document).write(to: url, options: .atomic) } catch {
      throw SettingsStoreError.unwritable(file: url.path)
    }
  }

  private func read(_ url: URL) throws -> SettingsDocument {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return SettingsDocument()
    } catch { throw SettingsStoreError.damaged(file: url.path) }
    do {
      return try JSONDecoder().decode(SettingsDocument.self, from: data)
    } catch let problem as SettingsHeaderProblem {
      throw SettingsStoreError.unsupported(problem.problem.located(in: url.path))
    } catch { throw SettingsStoreError.damaged(file: url.path) }
  }
}
