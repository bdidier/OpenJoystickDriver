import Foundation
import OpenJoystickDriverKit

/// A failure of a library operation: the message to show and the error code `ojd explain` knows.
struct LibraryFailure: Error, Equatable {
  let message: String
  let code: ErrorCode?
}

/// A controller record: a bundled one, or one that a user file or an installed package adds or
/// patches.
struct LibraryRecordItem: Equatable, Identifiable {
  let model: ControllerModelID
  let family: String
  let layer: ControllerRecordLayer
  let file: URL?

  var id: ControllerModelID { model }
  var identity: String { model.description }
  /// Only a record that a user file adds or patches can be removed here; a package's record
  /// goes with its package.
  var isRemovable: Bool { layer == .user }

  /// Whether the record's `VVVV:PPPP`, or its family, contains `query`, ignoring case. An empty
  /// query matches every record.
  func matches(_ query: String) -> Bool {
    Self.contains(query, in: [identity, family])
  }

  static func contains(_ query: String, in fields: [String]) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty
      || fields.contains { $0.range(of: query, options: .caseInsensitive) != nil }
  }
}

/// A file in the record directory that OJD skipped, and why.
struct LibrarySkippedFile: Equatable, Identifiable {
  let path: String
  let problem: String

  var id: String { path }
}

struct LibraryRecordListing: Equatable {
  /// Every effective record, by model.
  var items: [LibraryRecordItem] = []
  var skipped: [LibrarySkippedFile] = []

  /// The records that a user file or a package adds or patches.
  var installed: [LibraryRecordItem] { items.filter { $0.layer != .bundled } }
  /// The records the app comes with, no file of which changes them.
  var builtIn: [LibraryRecordItem] { items.filter { $0.layer == .bundled } }
}

/// A top-level field of a record and the layer that sets it.
struct LibraryRecordField: Equatable, Identifiable {
  let name: String
  let layer: ControllerRecordLayer

  var id: String { name }
}

/// Everything `ojd record show` prints for one record.
struct LibraryRecordDetail: Equatable {
  let item: LibraryRecordItem
  /// How OJD reaches the controller: `HID` or `USB`.
  let transport: String
  /// Why OJD reaches the controller only in a limited way, in words.
  let notes: [String]
  let fields: [LibraryRecordField]
  /// The effective record as JSON text; nil when it is not UTF-8.
  let document: String?
}

/// The outcome of replaying a capture through a record's parser.
struct LibraryTestRun: Equatable {
  let model: ControllerModelID
  /// The name of the expectation file.
  let expectation: String
  let result: ControllerRecordTestResult
}

/// What validation found in a record file.
struct LibraryRecordCheck: Equatable {
  let identity: String
  let family: String?
  let operation: ControllerRecordOperation
  let fileName: String
  /// Whether the record directory already holds a file of this name.
  let replaces: Bool
}

struct LibraryModItem: Equatable, Identifiable {
  let name: String
  let version: String?
  let author: String?
  let files: [String]
  /// Why the package is not used, or nil when it is.
  let problem: String?

  var id: String { name }

  /// Whether the mod's name contains `query`, ignoring case. An empty query matches every mod.
  func matches(_ query: String) -> Bool { LibraryRecordItem.contains(query, in: [name]) }
}

/// What validation found in a mod package folder.
struct LibraryModCheck: Equatable {
  let name: String
  let version: String
  let author: String
  let files: [String]
  /// Whether a package of this name is installed.
  let replaces: Bool
}

/// The controller records and mod packages the Library area lists, validates, installs and
/// removes. The operations are those of `ojd record` and `ojd mod`.
protocol LibraryStore: Sendable {
  func records() -> LibraryRecordListing
  func recordDetail(_ model: ControllerModelID) -> LibraryRecordDetail?
  /// Replays the capture through the record's parser and compares the state with the
  /// expectation. The names label the files in a failure.
  func testRecord(
    _ model: ControllerModelID,
    capture: Data,
    captureName: String,
    expectation: Data,
    expectationName: String
  ) throws -> ControllerRecordTestResult
  func checkRecord(_ data: Data) throws -> LibraryRecordCheck
  func installRecord(_ data: Data) throws -> LibraryRecordCheck
  func removeRecord(_ model: ControllerModelID) throws
  func installedMods() -> [LibraryModItem]
  func checkMod(folder: URL) throws -> LibraryModCheck
  func installMod(folder: URL, replace: Bool) throws
  func removeMod(name: String) throws
}

/// The store on disk: user records in `recordsDirectory`, packages beside it.
struct DirectoryLibraryStore: LibraryStore {
  let recordsDirectory: URL
  let packagesDirectory: URL
  let runningVersion: String?

  init(
    recordsDirectory: URL = ControllerRecordSet.userDirectory,
    runningVersion: String? = nil
  ) {
    self.recordsDirectory = recordsDirectory
    packagesDirectory = ModPackageStore.directory(besides: recordsDirectory)
    self.runningVersion = runningVersion
  }

  private var packages: ModPackageStore {
    ModPackageStore(directory: packagesDirectory, runningVersion: runningVersion)
  }

  func records() -> LibraryRecordListing {
    let set = ControllerRecordSet.load(userDirectory: recordsDirectory)
    return LibraryRecordListing(
      items: set.records.values.sorted { $0.model < $1.model }.map(Self.item),
      skipped: set.userFiles.compactMap { file in
        file.problem.map { LibrarySkippedFile(path: file.url.path, problem: $0) }
      }
    )
  }

  private static func item(_ record: ControllerRecord) -> LibraryRecordItem {
    LibraryRecordItem(
      model: record.model,
      family: CommandLineName.kebab(record.family),
      layer: record.layer,
      file: record.file
    )
  }

  func recordDetail(_ model: ControllerModelID) -> LibraryRecordDetail? {
    guard let record = ControllerRecordSet.load(userDirectory: recordsDirectory).records[model]
    else { return nil }
    var notes: [String] = []
    if record.isClaimedByUSBExtension == false {
      notes.append(OJDLocalized.string("cli.record.usb_not_claimed"))
    }
    if record.isSwitch2WithoutBluetoothLE {
      notes.append(OJDLocalized.string("cli.record.usb_only_switch2"))
    }
    return LibraryRecordDetail(
      item: Self.item(record),
      transport: record.usesRawUSB ? "USB" : "HID",
      notes: notes,
      fields: record.fieldLayers.sorted { $0.key < $1.key }.map {
        LibraryRecordField(name: $0.key, layer: $0.value)
      },
      document: String(bytes: record.document, encoding: .utf8)
    )
  }

  func testRecord(
    _ model: ControllerModelID,
    capture: Data,
    captureName: String,
    expectation: Data,
    expectationName: String
  ) throws -> ControllerRecordTestResult {
    guard let record = ControllerRecordSet.load(userDirectory: recordsDirectory).records[model]
    else {
      throw LibraryFailure(
        message: OJDLocalized.formatted("library.record.notFound", model.description),
        code: .notFound
      )
    }
    do { return try record.test(capture: capture, expectation: expectation) } catch let error
      as ControllerRecordTestError
    {
      throw LibraryFailure(
        message: error.message(
          model: model,
          capture: captureName,
          expectation: expectationName
        ),
        code: .invalidInputFile
      )
    }
  }

  func checkRecord(_ data: Data) throws -> LibraryRecordCheck {
    let validated: ValidatedControllerRecord
    do { validated = try ControllerRecordSet.validate(data) } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "library.record.invalid",
          ControllerRecordSet.problemDescription(error, includingCode: false)
        ),
        code: ControllerRecordSet.problemCode(error) ?? .invalidInputFile
      )
    }
    let destination = recordsDirectory.appendingPathComponent(validated.fileName)
    return LibraryRecordCheck(
      identity: Self.identity(of: validated),
      family: validated.record.map { CommandLineName.kebab($0.family) },
      operation: validated.operation,
      fileName: validated.fileName,
      replaces: FileManager.default.fileExists(atPath: destination.path)
    )
  }

  /// A validated file is a Controller file with a record or a patch with a selector.
  private static func identity(of validated: ValidatedControllerRecord) -> String {
    if let record = validated.record { return record.model.description }
    if let selector = validated.selector { return selector.description }
    preconditionFailure("A validated controller record file has a record or a selector")
  }

  func installRecord(_ data: Data) throws -> LibraryRecordCheck {
    let check = try checkRecord(data)
    let destination = recordsDirectory.appendingPathComponent(check.fileName)
    do {
      try FileManager.default.createDirectory(
        at: recordsDirectory,
        withIntermediateDirectories: true
      )
      try data.write(to: destination, options: .atomic)
    } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "library.record.installFailed",
          destination.path,
          error.localizedDescription
        ),
        code: .fileAccessFailed
      )
    }
    return check
  }

  func removeRecord(_ model: ControllerModelID) throws {
    let targets = [
      ControllerRecordSet.fileName(for: model), ControllerPatch.Selector.identity(model).fileName,
    ].map { recordsDirectory.appendingPathComponent($0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !targets.isEmpty else {
      throw LibraryFailure(
        message: OJDLocalized.formatted("library.record.notFound", model.description),
        code: .notFound
      )
    }
    for target in targets {
      do { try FileManager.default.removeItem(at: target) } catch {
        throw LibraryFailure(
          message: OJDLocalized.formatted(
            "library.record.removeFailed",
            target.path,
            error.localizedDescription
          ),
          code: .fileAccessFailed
        )
      }
    }
  }

  func installedMods() -> [LibraryModItem] {
    packages.list().map { package in
      LibraryModItem(
        name: package.name,
        version: package.manifest?.version,
        author: package.manifest?.author,
        files: package.manifest.map(Self.listedFiles) ?? [],
        problem: package.problem
      )
    }
  }

  func checkMod(folder: URL) throws -> LibraryModCheck {
    do {
      let manifest = try packages.validate(folder)
      let installed = packagesDirectory.appendingPathComponent(manifest.name, isDirectory: true)
      return LibraryModCheck(
        name: manifest.name,
        version: manifest.version,
        author: manifest.author,
        files: Self.listedFiles(of: manifest),
        replaces: (try? FileManager.default.attributesOfItem(atPath: installed.path)) != nil
      )
    } catch let error as ModPackageError {
      throw Self.failure(error, subject: folder.path)
    }
  }

  func installMod(folder: URL, replace: Bool) throws {
    do { _ = try packages.install(folder, replace: replace) } catch let error as ModPackageError {
      throw Self.failure(error, subject: folder.path)
    }
  }

  func removeMod(name: String) throws {
    do { try packages.remove(name) } catch let error as ModPackageError {
      throw Self.failure(error, subject: name)
    }
  }

  private static func failure(_ error: ModPackageError, subject: String) -> LibraryFailure {
    LibraryFailure(
      message: OJDLocalized.formatted("library.mod.refused", subject, error.detail),
      code: error.code
    )
  }

  private static func listedFiles(of manifest: ModPackageManifest) -> [String] {
    manifest.records.map { "Controllers/\($0)" } + manifest.profiles.map { "Profiles/\($0)" }
      + manifest.personas.map { "Personas/\($0)" }
  }
}
