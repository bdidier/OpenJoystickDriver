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

/// Reads and writes the layered `Settings.json` files through the `DataDirectory` port.
///
/// The layers, lowest to highest precedence:
/// 1. the built-in defaults (``ApplicationSettingKey/defaultValue``);
/// 2. the machine file in ``DataLocation/machineData``, which only an administrator writes;
/// 3. the user file in ``DataLocation/applicationData``, which is the only file OJD writes.
///
/// A missing file is an empty layer. A damaged or unsupported file is an error, never an empty
/// layer, so a mistake does not silently reset settings. Updates are atomic read-modify-write
/// within one process; two processes updating at the same moment can lose one update.
public struct SettingsStore: Sendable {
  public static let fileName = "Settings.json"
  /// The locations whose `Settings.json` is read, lowest precedence first.
  public static let layers: [DataLocation] = [.machineData, .applicationData]
  /// The location that is written.
  public static let writableLayer = DataLocation.applicationData

  private static let writeLock = NSLock()

  private let directory: any DataDirectory

  public init(directory: any DataDirectory = MacOSDataDirectory()) { self.directory = directory }

  /// The path of the user file.
  public var userFileURL: URL { directory.fileURL(Self.fileName, in: Self.writableLayer) }

  /// Every layer merged: the stored value of each setting that any file sets.
  public func load() throws -> SettingsDocument {
    try Self.layers.reduce(SettingsDocument()) { lower, location in
      lower.overlaid(by: try read(directory.fileURL(Self.fileName, in: location)))
    }
  }

  /// The value of `key` after the layers and the built-in default apply.
  public func value(of key: ApplicationSettingKey) throws -> Bool {
    try load()[key] ?? key.defaultValue
  }

  /// Whether the user turned launch at login off, so the app must not register itself again.
  public func launchAtLoginOptOut() throws -> Bool { try load().launchAtLoginOptOut ?? false }

  /// Stores `value` for `key` in the user file; the machine file is never written.
  public func set(_ key: ApplicationSettingKey, to value: Bool) throws {
    try update([key: value])
  }

  /// Stores every value in `values` in the user file in one write.
  public func update(_ values: [ApplicationSettingKey: Bool]) throws {
    Self.writeLock.lock()
    defer { Self.writeLock.unlock() }
    let url = userFileURL
    var document = try read(url)
    for (key, value) in values { document[key] = value }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try encoder.encode(document).write(to: url, options: .atomic)
    } catch { throw SettingsStoreError.unwritable(file: url.path) }
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
