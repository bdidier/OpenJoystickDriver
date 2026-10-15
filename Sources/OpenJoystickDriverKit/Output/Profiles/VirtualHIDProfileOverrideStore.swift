import Foundation

/// Why the persona directory cannot be read.
public enum VirtualHIDProfileOverrideError: Error, Equatable, Sendable {
  /// The directory exists but cannot be listed, created, or written.
  case unreadableDirectory(String)
}

/// One persona: a built-in report descriptor and, optionally, the identity published over it.
public struct VirtualPersona: Equatable, Sendable {
  /// The identity strings, IDs, and glyph family a user defined over the descriptor.
  public struct Identity: Equatable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let versionNumber: Int?
    public let productName: String
    public let manufacturer: String
    public let glyphFamily: VirtualIdentityGlyphFamily
  }

  public let descriptor: VirtualHIDProfileID
  /// Nil for a persona that only selects the descriptor, which `ojd virtual` writes.
  public let identity: Identity?
}

/// One file in the persona directory and whether OJD applied it.
public struct VirtualPersonaFile: Equatable, Sendable {
  public let url: URL
  /// Why OJD skipped the file, or nil when it applied it.
  public let problem: String?
}

/// Per-controller-model and per-unit personas, stored as `Personas/<id>.json` files that follow
/// `persona.schema.json`.
///
/// A file matches a VID:PID model, or one unit of it (see ``ControllerPortKey``). A unit's persona
/// wins over its model's. A file that fails validation, or repeats the match of an earlier file in
/// file-name order, is skipped and listed in ``problems``. A missing directory holds no personas.
/// `set` writes `vvvv-pppp.json` or `vvvv-pppp-<unit>.json`, and keeps the identity of a persona
/// that already matches.
public struct VirtualHIDProfileOverrideStore: Sendable {
  /// The `kind` of a persona file.
  public static let kind = "Persona"

  /// `~/Library/Application Support/OpenJoystickDriver/Personas`.
  public static var userDirectory: URL {
    ControllerDefaults.userFile.deletingLastPathComponent()
      .appendingPathComponent("Personas", isDirectory: true)
  }

  /// A controller model, or one unit of it when `unit` is set.
  struct Model: Hashable {
    let vendorID: UInt16
    let productID: UInt16
    var unit: String?

    var fileName: String {
      String(format: "%04x-%04x", vendorID, productID) + (unit.map { "-\($0)" } ?? "") + ".json"
    }
  }

  private struct Found {
    let persona: VirtualPersona
    let url: URL
    /// Whether an installed package holds the file. A package file is never written or removed.
    var fromPackage = false
  }

  private struct Loaded {
    var personas: [Model: Found] = [:]
    var files: [VirtualPersonaFile] = []
  }

  private let directory: URL
  private let packages: ModPackageStore

  /// The store of `directory`, with the personas of the packages installed in the `Packages`
  /// folder beside it, or in `packagesDirectory`, under it. `runningVersion` is the OJD version
  /// that the `requires` of a package is checked against; nil means the running one.
  public init(
    directory: URL = Self.userDirectory,
    packagesDirectory: URL? = nil,
    runningVersion: String? = nil
  ) {
    self.directory = directory
    packages = ModPackageStore(
      directory: packagesDirectory ?? ModPackageStore.directory(besides: directory),
      runningVersion: runningVersion
    )
  }

  /// Why the directory cannot be read; nil when it is absent or readable.
  public var loadError: VirtualHIDProfileOverrideError? {
    if case .failure(let error) = load() { return error }
    return nil
  }

  /// Every file in the directory, in file-name order, with the reason OJD skipped it.
  public var files: [VirtualPersonaFile] {
    if case .success(let loaded) = load() { return loaded.files }
    return []
  }

  /// The files OJD skipped.
  public var problems: [VirtualPersonaFile] { files.filter { $0.problem != nil } }

  /// The persona for one controller: the one for `unit`, else the one for its model; nil when it
  /// selects automatically.
  public func persona(vendorID: UInt16, productID: UInt16, unit: String? = nil) -> VirtualPersona? {
    guard case .success(let loaded) = load() else { return nil }
    if let unit,
      let found = loaded.personas[Model(vendorID: vendorID, productID: productID, unit: unit)]
    {
      return found.persona
    }
    return loaded.personas[Model(vendorID: vendorID, productID: productID)]?.persona
  }

  /// The descriptor of ``persona(vendorID:productID:unit:)``.
  public func override(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) -> VirtualHIDProfileID? {
    persona(vendorID: vendorID, productID: productID, unit: unit)?.descriptor
  }

  /// The descriptor stored for exactly this model, or this unit when `unit` is set.
  public func storedOverride(
    vendorID: UInt16,
    productID: UInt16,
    unit: String?
  ) -> VirtualHIDProfileID? {
    guard case .success(let loaded) = load() else { return nil }
    return loaded.personas[Model(vendorID: vendorID, productID: productID, unit: unit)]?
      .persona.descriptor
  }

  /// Stores `profile` as the descriptor of one controller model, or of one unit of it.
  ///
  /// - Throws: The load error while the directory cannot be read or written.
  public func set(
    _ profile: VirtualHIDProfileID,
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws(VirtualHIDProfileOverrideError) {
    let model = Model(vendorID: vendorID, productID: productID, unit: unit)
    let existing = try load().get().personas[model]
    if existing?.persona.descriptor == profile { return }
    var match: [String: Any] = ["vendorID": Int(vendorID), "productID": Int(productID)]
    match["unit"] = unit
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": Self.kind, "match": match,
      "descriptor": profile.rawValue,
    ]
    if let identity = existing?.persona.identity {
      var fields: [String: Any] = [
        "vendorID": Int(identity.vendorID), "productID": Int(identity.productID),
        "productName": identity.productName, "manufacturer": identity.manufacturer,
        "glyphFamily": identity.glyphFamily.rawValue,
      ]
      fields["versionNumber"] = identity.versionNumber
      document["identity"] = fields
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try JSONSerialization.data(
        withJSONObject: document,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
      try data.write(
        to: existing.flatMap { $0.fromPackage ? nil : $0.url }
          ?? directory.appendingPathComponent(model.fileName),
        options: .atomic
      )
    } catch { throw .unreadableDirectory(error.localizedDescription) }
  }

  /// Returns one controller model, or one unit of it, to automatic selection by removing its
  /// descriptor-only persona file. Resetting a unit leaves its model's persona in effect, and a
  /// persona with a custom identity stays: delete its file to remove it.
  ///
  /// - Throws: The load error while the directory cannot be read or written.
  public func reset(
    vendorID: UInt16,
    productID: UInt16,
    unit: String? = nil
  ) throws(VirtualHIDProfileOverrideError) {
    let loaded = try load().get()
    guard let found = loaded.personas[Model(vendorID: vendorID, productID: productID, unit: unit)],
      found.persona.identity == nil, !found.fromPackage
    else { return }
    do { try FileManager.default.removeItem(at: found.url) } catch {
      throw .unreadableDirectory(error.localizedDescription)
    }
  }

  /// Removes every descriptor-only persona file. Files with a custom identity and files OJD
  /// skipped stay.
  public func resetAll() {
    guard case .success(let loaded) = load() else { return }
    for found in loaded.personas.values where found.persona.identity == nil && !found.fromPackage {
      try? FileManager.default.removeItem(at: found.url)
    }
  }

  private func load() -> Result<Loaded, VirtualHIDProfileOverrideError> {
    loadUserFiles().map { user in
      var loaded = user
      addPackageFiles(to: &loaded)
      return loaded
    }
  }

  /// Adds the personas of the installed packages, in package-name order. A package that cannot be
  /// used, such as one whose `requires` leaves out the running version, adds none, and its
  /// `mod.json` is listed with the reason. A persona whose match a user file or an earlier package
  /// already holds is skipped and listed with that reason.
  private func addPackageFiles(to loaded: inout Loaded) {
    for package in packages.list() {
      if let problem = package.problem {
        loaded.files.append(
          VirtualPersonaFile(
            url: package.directory.appendingPathComponent(ModPackageManifest.fileName),
            problem: problem
          )
        )
        continue
      }
      for file in package.manifest?.personas.sorted() ?? [] {
        let url = package.directory.appendingPathComponent("Personas/\(file)")
        do {
          let (model, persona) = try Self.parse(Data(contentsOf: url))
          if let first = loaded.personas[model] {
            let owner = first.fromPackage ? "package file " : "user file "
            throw ControllerRecordProblem("same match as \(owner)\(first.url.lastPathComponent)")
          }
          loaded.personas[model] = Found(persona: persona, url: url, fromPackage: true)
          loaded.files.append(VirtualPersonaFile(url: url, problem: nil))
        } catch {
          loaded.files.append(
            VirtualPersonaFile(url: url, problem: ControllerRecordSet.problemDescription(error))
          )
        }
      }
    }
  }

  private func loadUserFiles() -> Result<Loaded, VirtualHIDProfileOverrideError> {
    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch CocoaError.fileReadNoSuchFile {
      return .success(Loaded())
    } catch { return .failure(.unreadableDirectory(error.localizedDescription)) }
    var loaded = Loaded()
    for url in urls {
      do {
        let (model, persona) = try Self.parse(Data(contentsOf: url))
        if let first = loaded.personas[model] {
          throw ControllerRecordProblem("same match as \(first.url.lastPathComponent)")
        }
        loaded.personas[model] = Found(persona: persona, url: url)
        loaded.files.append(VirtualPersonaFile(url: url, problem: nil))
      } catch {
        loaded.files.append(
          VirtualPersonaFile(url: url, problem: ControllerRecordSet.problemDescription(error))
        )
      }
    }
    return .success(loaded)
  }

  /// Decodes one `persona.schema.json` document.
  static func parse(_ data: Data) throws -> (Model, VirtualPersona) {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let document = object as? [String: Any]
    else { throw ControllerRecordProblem("the file is not a JSON object") }
    try OpenJoystickDriverAPI.requireHeader(document, kind: kind)
    guard
      Set(document.keys).isSubset(of: [
        "apiVersion", "kind", "match", "descriptor", "identity",
      ]), document["match"] != nil, document["descriptor"] != nil
    else {
      throw ControllerRecordProblem("the file must hold apiVersion, kind, match, and descriptor")
    }
    guard let descriptor = (document["descriptor"] as? String).flatMap(VirtualHIDProfileID.init)
    else { throw ControllerRecordProblem("descriptor must be hid-xbox-one-s-bt or hid-generic") }
    let match = try fields(document["match"], named: "match", optional: ["unit"])
    let unit = match["unit"] as? String
    if match["unit"] != nil, unit.flatMap(ControllerPortKey.init(rawValue:)) == nil {
      throw ControllerRecordProblem("match.unit is not a unit ID")
    }
    let model = Model(
      vendorID: try id(match["vendorID"], "match.vendorID", from: 1),
      productID: try id(match["productID"], "match.productID", from: 0),
      unit: unit
    )
    return (model, VirtualPersona(descriptor: descriptor, identity: try identity(document)))
  }

  private static func identity(_ document: [String: Any]) throws -> VirtualPersona.Identity? {
    guard document["identity"] != nil else { return nil }
    let fields = try fields(
      document["identity"],
      named: "identity",
      required: ["vendorID", "productID", "productName", "manufacturer", "glyphFamily"],
      optional: ["versionNumber"]
    )
    func text(_ key: String) throws -> String {
      guard let value = fields[key] as? String, !value.isEmpty else {
        throw ControllerRecordProblem("identity.\(key) must be a nonempty string")
      }
      return value
    }
    guard let glyph = VirtualIdentityGlyphFamily(rawValue: try text("glyphFamily")) else {
      throw ControllerRecordProblem("identity.glyphFamily must be xbox or generic")
    }
    let version = try fields["versionNumber"].map { try id($0, "identity.versionNumber", from: 0) }
    return VirtualPersona.Identity(
      vendorID: try id(fields["vendorID"], "identity.vendorID", from: 1),
      productID: try id(fields["productID"], "identity.productID", from: 0),
      versionNumber: version.map(Int.init),
      productName: try text("productName"),
      manufacturer: try text("manufacturer"),
      glyphFamily: glyph
    )
  }

  private static func fields(
    _ value: Any?,
    named name: String,
    required: Set<String> = ["vendorID", "productID"],
    optional: Set<String>
  ) throws -> [String: Any] {
    guard let object = value as? [String: Any],
      Set(object.keys).isSubset(of: required.union(optional)),
      required.isSubset(of: Set(object.keys))
    else {
      throw ControllerRecordProblem(
        "\(name) must hold \(required.union(optional).sorted().joined(separator: ", "))"
      )
    }
    return object
  }

  private static func id(_ value: Any?, _ name: String, from minimum: Int) throws -> UInt16 {
    // swiftlint:disable:next legacy_objc_type
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let integer = Int(exactly: number.doubleValue), integer >= minimum,
      let id = UInt16(exactly: integer)
    else { throw ControllerRecordProblem("\(name) must be \(minimum)...65535") }
    return id
  }
}
