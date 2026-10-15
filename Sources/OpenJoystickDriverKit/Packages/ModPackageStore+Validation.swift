import Foundation

/// What a set of package or user files covers: controller identities, personas, and profiles.
private struct ModPackageClaims {
  var records: Set<String> = []
  var personas: Set<String> = []
  var profileIDs: Set<UUID> = []
  var profileNames: Set<String> = []

  /// Records a profile, and returns false when this set already holds its UUID or name.
  mutating func add(_ profile: RemappingProfile) -> Bool {
    let name = profile.name.lowercased(with: Locale(identifier: "en_US_POSIX"))
    return profileIDs.insert(profile.id).inserted && profileNames.insert(name).inserted
  }

  /// The first item that both sets cover, or nil.
  func clash(with other: Self) -> String? {
    if let file = records.intersection(other.records).min() { return "Controllers/\(file)" }
    if let file = personas.intersection(other.personas).min() { return "Personas/\(file)" }
    if let id = profileIDs.intersection(other.profileIDs).min(by: { $0.uuidString < $1.uuidString })
    {
      return "profile \(id.uuidString)"
    }
    if let name = profileNames.intersection(other.profileNames).min() {
      return "profile named \(name)"
    }
    return nil
  }
}

extension ModPackageStore {
  /// Checks the package in `folder`: its manifest, that it runs on this version, that its files
  /// are the listed ones and valid, and that none clashes with the user's files or another
  /// installed package. A package of the same name is the one an install replaces, so it is not
  /// a clash.
  ///
  /// - Returns: The manifest.
  /// - Throws: ``ModPackageError`` with the E4xxx code of the first problem.
  @discardableResult
  public func validate(_ folder: URL) throws -> ModPackageManifest {
    try Self.checkLayout(of: folder)
    let manifest = try Self.manifest(in: folder)
    if let problem = requiresProblem(of: manifest) { throw problem }
    let claims = try Self.checkedClaims(of: folder, manifest)
    let user = userRoot
    var holders: [(label: String, claims: ModPackageClaims)] = [
      ("your own files", Self.userClaims(user))
    ]
    // A package that cannot be used, such as one whose `requires` leaves out this version, holds
    // nothing, so it does not block its replacement or another package.
    for other in list() where other.name != manifest.name && other.problem == nil {
      if let held = other.manifest {
        holders.append(("package \(other.name)", Self.claims(of: other.directory, held)))
      }
    }
    for holder in holders {
      if let item = claims.clash(with: holder.claims) {
        throw ModPackageError(.packageClash, "\(item) clashes with \(holder.label)")
      }
    }
    return manifest
  }

  private var userRoot: URL { directory.deletingLastPathComponent() }

  /// The E4002 refusal of `manifest` on the running version, or nil when its `requires` admits
  /// that version. A running version that is not a SemVer version is refused.
  func requiresProblem(of manifest: ModPackageManifest) -> ModPackageError? {
    guard let running = SemanticVersion(runningVersion) else {
      return ModPackageError(
        .requiresExcludesVersion,
        "the running version \(runningVersion) is not a SemVer version"
      )
    }
    guard manifest.requires.admits(running) else {
      let range =
        "\(manifest.requires.minimum)"
        + (manifest.requires.below.map { " up to \($0)" } ?? " or later")
      return ModPackageError(
        .requiresExcludesVersion,
        "\(manifest.name) requires \(range), and this is \(runningVersion)"
      )
    }
    return nil
  }

  /// The claims of `folder`, after every listed file is present and valid and no file is unlisted.
  private static func checkedClaims(
    of folder: URL,
    _ manifest: ModPackageManifest
  ) throws -> ModPackageClaims {
    var claims = ModPackageClaims()
    let kinds = [
      ("Controllers", manifest.records), ("Profiles", manifest.profiles),
      ("Personas", manifest.personas),
    ]
    for (kind, listed) in kinds {
      let present = Set(
        (try? FileManager.default.contentsOfDirectory(
          at: folder.appendingPathComponent(kind),
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        ))?.map(\.lastPathComponent) ?? []
      )
      if let file = Set(listed).subtracting(present).min() {
        throw ModPackageError(.invalidPackageContent, "\(kind)/\(file) is listed and missing")
      }
      if let file = present.subtracting(listed).min() {
        throw ModPackageError(.invalidPackageContent, "\(kind)/\(file) is not listed in mod.json")
      }
    }
    for file in manifest.records {
      let url = folder.appendingPathComponent("Controllers/\(file)")
      let record = try content(url, "Controllers/\(file)") {
        try ControllerRecordSet.validate($0, file: url, layer: .package).record
      }
      guard file == ControllerRecordSet.fileName(for: record.model) else {
        throw ModPackageError(
          .invalidPackageContent,
          "Controllers/\(file): the file name must be "
            + ControllerRecordSet.fileName(for: record.model)
        )
      }
      claims.records.insert(file)
    }
    for file in manifest.personas {
      let url = folder.appendingPathComponent("Personas/\(file)")
      let model = try content(url, "Personas/\(file)") {
        try VirtualHIDProfileOverrideStore.parse($0).0
      }
      guard file == model.fileName else {
        throw ModPackageError(
          .invalidPackageContent,
          "Personas/\(file): the file name must be \(model.fileName)"
        )
      }
      claims.personas.insert(file)
    }
    for file in manifest.profiles {
      let url = folder.appendingPathComponent("Profiles/\(file)")
      let profile = try content(url, "Profiles/\(file)") {
        try RemappingProfileFileStore.load(from: $0)
      }
      guard claims.add(profile) else {
        throw ModPackageError(
          .packageClash,
          "Profiles/\(file) repeats the UUID or name of another profile of the package"
        )
      }
    }
    return claims
  }

  /// Refuses a link anywhere in `folder`, and an entry beside `mod.json` that is not one of the
  /// three kind folders. Hidden entries are skipped here, and an install does not copy them.
  private static func checkLayout(of folder: URL) throws {
    guard !isLink(folder) else {
      throw ModPackageError(.invalidPackageContent, "\(folder.lastPathComponent) is a link")
    }
    let known: Set = [ModPackageManifest.fileName, "Controllers", "Profiles", "Personas"]
    let entries = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    if let name = (entries ?? []).map(\.lastPathComponent).filter({ !known.contains($0) }).min() {
      throw ModPackageError(.invalidPackageContent, "\(name) is not part of a package")
    }
    let walk = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    while let url = walk?.nextObject() as? URL {
      if isLink(url) {
        throw ModPackageError(.invalidPackageContent, "\(url.lastPathComponent) is a link")
      }
    }
  }

  /// Reads `url` and runs `check` on it, and turns each failure into E4003 naming `label`, or
  /// into E5001 when the file's `apiVersion` is not supported.
  private static func content<Value>(
    _ url: URL,
    _ label: String,
    _ check: (Data) throws -> Value
  ) throws -> Value {
    do { return try check(Data(contentsOf: url)) } catch {
      throw ModPackageError(
        ControllerRecordSet.problemCode(error) ?? .invalidPackageContent,
        "\(label): \(ControllerRecordSet.problemDescription(error, includingCode: false))"
      )
    }
  }

  /// The claims of an installed package, from its listed files. A profile that cannot be read
  /// claims nothing.
  private static func claims(of folder: URL, _ manifest: ModPackageManifest) -> ModPackageClaims {
    var claims = ModPackageClaims()
    claims.records = Set(manifest.records)
    claims.personas = Set(manifest.personas)
    for file in manifest.profiles {
      if let profile = try? RemappingProfileFileStore.load(
        from: folder.appendingPathComponent("Profiles/\(file)")
      ) {
        _ = claims.add(profile)
      }
    }
    return claims
  }

  /// The claims of the user's `Controllers`, `Personas`, and `Profiles` folders in `root`.
  private static func userClaims(_ root: URL) -> ModPackageClaims {
    func files(_ kind: String) -> [URL] {
      let urls = try? FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent(kind),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      return (urls ?? []).filter { $0.pathExtension == "json" }
    }
    var claims = ModPackageClaims()
    claims.records = Set(files("Controllers").map(\.lastPathComponent))
    for url in files("Personas") {
      if let model = (try? VirtualHIDProfileOverrideStore.parse(Data(contentsOf: url)))?.0 {
        claims.personas.insert(model.fileName)
      }
    }
    for url in files("Profiles") {
      if let profile = try? RemappingProfileFileStore.load(from: url) { _ = claims.add(profile) }
    }
    return claims
  }
}
