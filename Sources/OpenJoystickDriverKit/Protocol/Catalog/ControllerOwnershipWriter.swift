import Foundation

/// Sets the `ownership` of one controller model in the user's controller-record directory.
///
/// An existing user file keeps every other key; only `ownership` is set or replaced. A missing
/// file becomes a ControllerPatch file when the bundled catalog or an installed package has the
/// model, because a patch applies over one of their records. The record watcher of the service
/// applies the change.
public enum ControllerOwnershipWriter {
  /// One planned change, before ``write(_:)`` stores it.
  public struct Change: Sendable {
    public let model: ControllerModelID
    public let ownership: ControllerOwnership
    /// The effective ownership before the change; `macos` when no layer sets it.
    public let previous: ControllerOwnership
    /// The user file the change writes.
    public let file: URL
    /// Whether the change creates the file.
    public let created: Bool
    /// The bytes ``write(_:)`` stores, a valid user record.
    public let data: Data
  }

  /// Why the change was refused. The file stays as it was.
  public enum Failure: Error, Equatable, Sendable {
    /// The user directory has no file for the model and neither the bundled catalog nor an
    /// installed package has a record of it, so there is nothing to patch. `ojd record draft`
    /// starts a Controller file.
    case noRecord
    /// The existing user file is invalid, with its problem.
    case invalidFile(String)
    /// The changed record is invalid, such as `ownership` on a raw-USB family, with its problem.
    case invalidResult(String)
  }

  /// The change that sets `ownership` for `model` in `directory`. `records` is the loaded
  /// record set, which gives the effective ownership before the change.
  public static func change(
    _ model: ControllerModelID,
    to ownership: ControllerOwnership,
    records: ControllerRecordSet,
    directory: URL = ControllerRecordSet.userDirectory
  ) throws(Failure) -> Change {
    let controllerFile = directory.appendingPathComponent(ControllerRecordSet.fileName(for: model))
    let patchFile = directory.appendingPathComponent(
      ControllerPatch.Selector.identity(model).fileName
    )
    let packages = ControllerRecordSet.packageRecords(
      in: ModPackageStore.directory(besides: directory)
    ).records
    let existingController = try? Data(contentsOf: controllerFile)
    let existing = existingController ?? (try? Data(contentsOf: patchFile))
    let file = existingController == nil ? patchFile : controllerFile
    let document: [String: Any]
    if let existing {
      document = try updated(existing, file: file, ownership: ownership, packages: packages)
    } else {
      guard packages[model] != nil else { throw .noRecord }
      document = ControllerPatch.document(
        selector: .identity(model),
        body: ["ownership": ownership.rawValue]
      )
    }
    let data: Data
    do {
      data = try JSONSerialization.data(
        withJSONObject: document,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
      _ = try ControllerRecordSet.validate(data, file: file, packages: packages)
    } catch { throw .invalidResult(ControllerRecordSet.problemDescription(error)) }
    return Change(
      model: model,
      ownership: ownership,
      previous: (records.records[model] ?? packages[model])?.profile.ownership ?? .macOS,
      file: file,
      created: existing == nil,
      data: data
    )
  }

  /// Stores `change` atomically, creating the user directory when it is missing.
  public static func write(_ change: Change) throws {
    try FileManager.default.createDirectory(
      at: change.file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try change.data.write(to: change.file, options: .atomic)
  }

  /// The existing user file with `ownership` set in the Controller file or in the `patch` of the
  /// ControllerPatch file.
  private static func updated(
    _ data: Data,
    file: URL,
    ownership: ControllerOwnership,
    packages: [ControllerModelID: ControllerRecord]
  ) throws(Failure) -> [String: Any] {
    let operation: ControllerRecordOperation
    do {
      operation = try ControllerRecordSet.validate(data, file: file, packages: packages).operation
    } catch { throw .invalidFile(ControllerRecordSet.problemDescription(error)) }
    guard var document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      throw .invalidFile("the file is not a JSON object")
    }
    if operation == .add {
      document["ownership"] = ownership.rawValue
    } else {
      var fields = document["patch"] as? [String: Any] ?? [:]
      fields["ownership"] = ownership.rawValue
      document["patch"] = fields
    }
    return document
  }
}
