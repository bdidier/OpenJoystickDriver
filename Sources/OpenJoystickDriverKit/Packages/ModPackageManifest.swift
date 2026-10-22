import Foundation

/// Why a mod package is refused, with the `mod` error code that names the kind of refusal.
public struct ModPackageError: Error, Equatable, Sendable, CustomStringConvertible {
  public let code: ErrorCode
  /// What is wrong and where, in words for the person who wrote the package.
  public let detail: String

  init(_ code: ErrorCode, _ detail: String) {
    self.code = code
    self.detail = detail
  }

  public var description: String { "\(code.rawValue): \(detail)" }
}

/// The `mod.json` of a package folder, from `mod-package.schema.json`.
public struct ModPackageManifest: Equatable, Sendable {
  /// The `kind` of a manifest.
  public static let kind = "ModPackage"
  public static let fileName = "mod.json"

  /// The OJD versions the package runs on: `minimum` up to, but not including, `below`.
  public struct Requires: Equatable, Sendable {
    public let minimum: String
    public let below: String?
  }

  public let name: String
  public let version: String
  public let author: String
  public let requires: Requires
  /// `Controller` files of the package's `Controllers/` folder.
  public let controllers: [String]
  /// `ControllerPatch` files of the package's `Controllers/` folder.
  public let patches: [String]
  /// Files of the package's `Profiles/` folder.
  public let profiles: [String]
  /// `VirtualDevice` files of the package's `VirtualDevices/` folder.
  public let virtualDevices: [String]

  /// The listed files as paths inside the package folder.
  public var listedFiles: [String] {
    controllers.map { "Controllers/\($0)" } + patches.map { "Controllers/\($0)" }
      + profiles.map { "Profiles/\($0)" } + virtualDevices.map { "VirtualDevices/\($0)" }
  }

  /// Decodes and checks one `mod.json`.
  ///
  /// - Throws: ``ModPackageError`` with ``ErrorCode/invalidManifest``.
  public static func parse(_ data: Data) throws -> Self {
    do { return try JSONDecoder().decode(Self.self, from: data) } catch let error
      as ModPackageError
    { throw error } catch let DecodingError.dataCorrupted(context) {
      throw ModPackageError(.invalidManifest, located(context))
    } catch let DecodingError.keyNotFound(key, context) {
      throw ModPackageError(.invalidManifest, located(context, "missing field \(key.stringValue)"))
    } catch let DecodingError.typeMismatch(_, context) {
      throw ModPackageError(.invalidManifest, located(context))
    } catch let DecodingError.valueNotFound(_, context) {
      throw ModPackageError(.invalidManifest, located(context))
    } catch { throw ModPackageError(.invalidManifest, error.localizedDescription) }
  }

  private static func located(_ context: DecodingError.Context, _ text: String? = nil) -> String {
    let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
    return (path.isEmpty ? "" : path.joined(separator: ".") + ": ")
      + (text ?? context.debugDescription)
  }
}

extension ModPackageManifest: Decodable {
  private enum Key: String, CodingKey, CaseIterable {
    case apiVersion, kind
    case name, version, author, requires, controllers, patches, profiles, virtualDevices
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(Key.self)
    let container = try decoder.container(keyedBy: Key.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      guard let code = problem.code else {
        throw ModPackageError(.invalidManifest, problem.message)
      }
      throw ModPackageError(code, "\(Self.fileName): \(problem.message)")
    }
    name = try container.decode(String.self, forKey: .name)
    guard name.range(of: "\\A[a-z0-9]+(-[a-z0-9]+)*\\z", options: .regularExpression) != nil else {
      throw ModPackageError(
        .invalidManifest,
        "name must hold lowercase letters, digits, and hyphens"
      )
    }
    version = try Self.semanticVersion(container.decode(String.self, forKey: .version), "version")
    author = try container.decode(String.self, forKey: .author)
    guard !author.isEmpty else { throw ModPackageError(.invalidManifest, "author is empty") }
    requires = try container.decode(Requires.self, forKey: .requires)
    controllers = try Self.files(container, .controllers, pattern: Self.controllerFilePattern)
    patches = try Self.files(container, .patches, pattern: Self.patchFilePattern)
    profiles = try Self.files(container, .profiles, pattern: Self.profileFilePattern)
    virtualDevices = try Self.files(
      container,
      .virtualDevices,
      pattern: Self.virtualDeviceFilePattern
    )
    guard !(controllers + patches + profiles + virtualDevices).isEmpty else {
      throw ModPackageError(
        .invalidManifest,
        "controllers, patches, profiles, or virtualDevices must list a file"
      )
    }
  }

  // The patterns of `mod-package.schema.json`, with `\A` and `\z` for the ECMA `^` and `$`, so
  // that a trailing newline fails. `ModPackageManifestSchemaTests` feeds both the same manifests.
  private static let controllerFilePattern = "\\A[0-9a-f]{4}-[0-9a-f]{4}\\.json\\z"
  private static let patchFilePattern =
    "\\A(?:(?:model-)?[0-9a-f]{4}-[0-9a-f]{4}\\.patch\\.json|all\\.patch\\.json)\\z"
  private static let profileFilePattern = "\\A[A-Za-z0-9][A-Za-z0-9._-]*\\.json\\z"
  private static let virtualDeviceFilePattern =
    "\\A[0-9a-f]{4}-[0-9a-f]{4}(-U-[A-Za-z0-9_-]{16})?\\.json\\z"
  private static let semanticVersionPattern =
    "\\A(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)"
    + "(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    + "(\\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?\\z"

  /// One file list: absent, or a non-empty list of unique names that match `pattern`.
  private static func files(
    _ container: KeyedDecodingContainer<Key>,
    _ key: Key,
    pattern: String
  ) throws -> [String] {
    guard let list = try container.decodeIfPresent([String].self, forKey: key) else { return [] }
    guard !list.isEmpty else {
      throw ModPackageError(.invalidManifest, "\(key.rawValue) is empty")
    }
    guard Set(list).count == list.count else {
      throw ModPackageError(.invalidManifest, "a file is listed twice")
    }
    for file in list where file.range(of: pattern, options: .regularExpression) == nil {
      throw ModPackageError(.invalidManifest, "\(key.rawValue): \(file) is not a valid file name")
    }
    return list
  }

  /// `value` when it is a SemVer 2.0.0 version without a `v` prefix or build metadata.
  static func semanticVersion(_ value: String, _ field: String) throws -> String {
    guard SemanticVersion(value) != nil,
      value.range(of: semanticVersionPattern, options: .regularExpression) != nil
    else {
      throw ModPackageError(.invalidManifest, "\(field) must be a SemVer version")
    }
    return value
  }
}

extension ModPackageManifest.Requires: Decodable {
  private enum Key: String, CodingKey, CaseIterable { case minimum, below }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(Key.self)
    let container = try decoder.container(keyedBy: Key.self)
    minimum = try ModPackageManifest.semanticVersion(
      container.decode(String.self, forKey: .minimum),
      "requires.minimum"
    )
    below = try container.decodeIfPresent(String.self, forKey: .below)
      .map { try ModPackageManifest.semanticVersion($0, "requires.below") }
  }

  /// Whether `version` is at least `minimum` and, when set, below `below`.
  func admits(_ version: SemanticVersion) -> Bool {
    guard let lowest = SemanticVersion(minimum), version >= lowest else { return false }
    guard let below, let highest = SemanticVersion(below) else { return true }
    return version < highest
  }
}
