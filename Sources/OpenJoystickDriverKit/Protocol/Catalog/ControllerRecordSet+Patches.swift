import Foundation

/// One file of a layer, and the package that holds it, or nil for the user's file.
struct ControllerLayerEntry {
  let url: URL
  let owner: String?
}

extension ControllerRecordSet {
  /// The bundled catalog with the records and patches of the installed packages applied, then
  /// those of the valid `.json` files in `directory`. A missing directory holds no records; one
  /// that cannot be read is listed in ``userFiles`` with its reason. `all.patch.json` in
  /// `directory` is the user's global ``ControllerDefaults``; it is the first patch of the user
  /// layer and is reported in ``defaults`` rather than in ``userFiles``.
  public static func load(userDirectory directory: URL = userDirectory) -> Self {
    var packaged = packageRecords(in: ModPackageStore.directory(besides: directory))
    var defaults = ControllerDefaults.load(from: ControllerDefaults.file(in: directory))
    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch CocoaError.fileReadNoSuchFile {
      urls = []
    } catch {
      let file = ControllerRecordFile(
        url: directory,
        model: nil,
        operation: nil,
        problem: "cannot read the directory: \(error.localizedDescription)"
      )
      return Self(
        records: packaged.records,
        userFiles: [file] + packaged.files,
        defaults: defaults
      )
    }
    var records = packaged.records
    let applied = applyLayer(
      urls.map { ControllerLayerEntry(url: $0, owner: nil) },
      layer: .user,
      to: &records
    )
    for (model, url) in applied.replaced { packaged.overridden(model, by: url) }
    if let all = applied.files.first(where: { $0.url == defaults.url }), defaults.problem == nil,
      let problem = all.problem
    {
      defaults = ControllerDefaults(
        url: defaults.url,
        tuning: defaults.tuning,
        problem: problem,
        patch: nil
      )
    }
    return Self(
      records: records,
      userFiles: applied.files.filter { $0.url != defaults.url } + packaged.files,
      defaults: defaults
    )
  }

  /// Applies the files of one layer to `records`: the Controller files first, which add or
  /// replace a record, then the patches in the order of ``ControllerPatchMerge/ordered(_:)``,
  /// with a package name breaking a tie. A file that fails is skipped and reported in the
  /// returned files, which follow the order of `entries`. `replaced` lists the models a user
  /// Controller file replaced.
  static func applyLayer(
    _ entries: [ControllerLayerEntry],
    layer: ControllerRecordLayer,
    to records: inout [ControllerModelID: ControllerRecord]
  ) -> (files: [ControllerRecordFile], replaced: [(ControllerModelID, URL)]) {
    var results: [URL: ControllerRecordFile] = [:]
    var patches: [(entry: ControllerLayerEntry, patch: ControllerPatch)] = []
    var owners: [ControllerModelID: String] = [:]
    var replaced: [(ControllerModelID, URL)] = []
    for entry in entries {
      do {
        let name = entry.url.lastPathComponent
        switch try parse(Data(contentsOf: entry.url), file: entry.url, layer: layer) {
        case .record(let record):
          guard name == fileName(for: record.model) else {
            throw ControllerRecordProblem("the file name must be \(fileName(for: record.model))")
          }
          if let owner = entry.owner {
            if let other = owners[record.model] {
              throw ControllerRecordProblem("same controller as package \(other)")
            }
            owners[record.model] = owner
          }
          records[record.model] = record
          if layer == .user { replaced.append((record.model, entry.url)) }
          results[entry.url] = ControllerRecordFile(
            url: entry.url,
            model: record.model,
            operation: .add,
            problem: nil
          )
        case .patch(let patch):
          guard name == patch.selector.fileName else {
            throw ControllerRecordProblem("the file name must be \(patch.selector.fileName)")
          }
          patches.append((entry, patch))
        }
      } catch {
        results[entry.url] = ControllerRecordFile(
          url: entry.url,
          model: nil,
          operation: nil,
          problem: problemDescription(error)
        )
      }
    }
    for (entry, patch) in ControllerPatchMerge.ordered(patches, by: { ($0.patch, $0.entry.owner) })
    {
      let targets = records.keys.filter { patch.selector.selects($0) }.sorted()
      var failure: String?
      if targets.isEmpty, patch.selector != .all {
        failure = "\(patch.selector.description) is not a known controller; use a Controller file"
      }
      for target in targets {
        do {
          records[target] = try apply(patch, to: records[target]!, layer: layer, file: entry.url)
        } catch { failure = failure ?? problemDescription(error) }
      }
      let model: ControllerModelID? =
        switch patch.selector {
        case .all: nil
        case .identity(let model): model
        case .model: targets.first
        }
      results[entry.url] = ControllerRecordFile(
        url: entry.url,
        model: model,
        operation: .patch,
        problem: failure
      )
    }
    return (entries.compactMap { results[$0.url] }, replaced)
  }

  /// A file of a layer, read.
  enum ParsedFile {
    case record(ControllerRecord)
    case patch(ControllerPatch)
  }

  /// Reads one Controller or ControllerPatch file. A document of any other kind is refused by the ControllerPatch header check.
  static func parse(_ data: Data, file: URL?, layer: ControllerRecordLayer) throws -> ParsedFile {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let document = object as? [String: Any]
    else { throw ControllerRecordProblem("the file is not a JSON object") }
    if document["kind"] as? String == ControllerRecordDocument.kind {
      try OpenJoystickDriverAPI.requireHeader(
        document,
        kind: ControllerRecordDocument.kind,
        file: file?.lastPathComponent
      )
      let decoded = try decode(document)
      guard bundled.records[decoded.model] == nil else {
        throw ControllerRecordProblem(
          "\(decoded.model) is a bundled controller; use a patch to change it"
        )
      }
      let layers = Dictionary(
        uniqueKeysWithValues: fieldNames(of: document).map { ($0, layer) }
      )
      return .record(
        try makeRecord(
          document,
          layers: layers,
          userFile: layer == .user ? file : nil,
          packageFile: layer == .package ? file : nil
        )
      )
    }
    return .patch(try ControllerPatch.parse(document, file: file?.lastPathComponent))
  }

  /// Validates one record file against the bundled catalog: a Controller file's shape and
  /// cross-field checks, or a ControllerPatch file's shape and the record it gives when applied
  /// over the bundled record of its selector. `file` becomes the record's
  /// ``ControllerRecord/userFile``, or its ``ControllerRecord/packageFile`` when `layer` is
  /// `package`. A patch of a model with no bundled record applies over its record in `packages`,
  /// the installed package records. An `all` patch gives no record; its `tuning` is range-checked.
  public static func validate(
    _ data: Data,
    file: URL? = nil,
    layer: ControllerRecordLayer = .user,
    packages: [ControllerModelID: ControllerRecord] = [:]
  ) throws -> ValidatedControllerRecord {
    switch try parse(data, file: file, layer: layer) {
    case .record(let record):
      return ValidatedControllerRecord(operation: .add, record: record, selector: nil)
    case .patch(let patch):
      if patch.selector == .all {
        _ = try ControllerDefaults.validate(data, file: file?.lastPathComponent)
        return ValidatedControllerRecord(operation: .patch, record: nil, selector: .all)
      }
      let upstream =
        bundled.records.values.sorted { $0.model < $1.model }
        .first { patch.selector.selects($0.model) }
        ?? packages.values.sorted { $0.model < $1.model }.first { patch.selector.selects($0.model) }
      guard let upstream else {
        throw ControllerRecordProblem(
          "\(patch.selector.description) is not a known controller; use a Controller file"
        )
      }
      return ValidatedControllerRecord(
        operation: .patch,
        record: try apply(patch, to: upstream, layer: layer, file: file),
        selector: patch.selector
      )
    }
  }

  /// `upstream` with `patch` merged in by ``ControllerPatchMerge/apply(_:to:)`` and validated as a
  /// record. An `all` patch sets only the tuning keys the family reads, and attributes them to
  /// ``ControllerRecordLayer/global``.
  static func apply(
    _ patch: ControllerPatch,
    to upstream: ControllerRecord,
    layer: ControllerRecordLayer,
    file: URL?
  ) throws -> ControllerRecord {
    guard let base = try JSONSerialization.jsonObject(with: upstream.document) as? [String: Any]
    else { throw ControllerRecordProblem("the record is not a JSON object") }
    let isAll = patch.selector == .all
    guard let body = ControllerPatchMerge.appliedBody(of: patch, to: base) else { return upstream }
    let merged = ControllerPatchMerge.apply(patch, to: base)
    if !isAll {
      let changed =
        try JSONSerialization.data(withJSONObject: merged, options: .sortedKeys)
        != JSONSerialization.data(withJSONObject: base, options: .sortedKeys)
      guard changed else {
        throw ControllerRecordProblem("the patch changes nothing in the record")
      }
    }
    var layers = upstream.fieldLayers
    var tuningLayers = upstream.tuningLayers
    for (key, value) in body {
      if !isAll { layers[key] = value is NSNull ? nil : layer }
      if key == "tuning" {
        if value is NSNull {
          tuningLayers = [:]
        } else {
          for (name, setting) in value as? [String: Any] ?? [:] {
            tuningLayers[name] = setting is NSNull ? nil : (isAll ? .global : layer)
          }
        }
      }
    }
    return try makeRecord(
      merged,
      layers: layers,
      tuningLayers: tuningLayers,
      userFile: layer == .user && !isAll ? file : upstream.userFile,
      packageFile: layer == .package && !isAll ? file : upstream.packageFile
    )
  }
}
