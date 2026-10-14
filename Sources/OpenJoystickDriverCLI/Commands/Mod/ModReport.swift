import Foundation
import OpenJoystickDriverKit

/// Where `ojd mod` reads and writes installed packages.
enum ModStore {
  /// The package store; tests replace it.
  @TaskLocal
  static var directory = ModPackageStore.rootDirectory

  /// The OJD version that a package's `requires` is checked against; tests replace it.
  @TaskLocal
  static var runningVersion: String?

  static var store: ModPackageStore {
    ModPackageStore(directory: directory, runningVersion: runningVersion)
  }

  /// The folder named by the `FOLDER` operand.
  static func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

  /// The failure that reports `error` with its E4xxx code.
  static func failure(_ error: ModPackageError, subject: String) -> CLIFailure {
    CLIFailure(error.code, CLILocalized.format("cli.mod.refused", subject, error.detail))
  }
}

/// The files a manifest lists, as paths inside the package.
private func listedFiles(of manifest: ModPackageManifest) -> [String] {
  manifest.records.map { "Controllers/\($0)" } + manifest.profiles.map { "Profiles/\($0)" }
    + manifest.personas.map { "Personas/\($0)" }
}

/// The `--json` result of `mod validate`, and the `package` of `mod install`.
struct ModPackageValidation: Encodable, Equatable {
  let valid: Bool
  let problem: String?
  let code: String?
  let name: String?
  let version: String?
  let author: String?
  let files: [String]?

  init(_ manifest: ModPackageManifest) {
    valid = true
    problem = nil
    code = nil
    name = manifest.name
    version = manifest.version
    author = manifest.author
    files = listedFiles(of: manifest)
  }

  init(_ error: ModPackageError) {
    valid = false
    problem = error.detail
    code = error.code.rawValue
    name = nil
    version = nil
    author = nil
    files = nil
  }

  /// Validates `folder`. A refused package prints `valid: false` with `--json` and fails with
  /// the E4xxx code of the refusal.
  static func check(_ folder: String) throws -> ModPackageManifest {
    do { return try ModStore.store.validate(ModStore.folder(folder)) } catch let error
      as ModPackageError
    {
      if CLIContext.current.format == .json { try CLIOutput.json(Self(error)) }
      throw ModStore.failure(error, subject: folder)
    }
  }
}

/// One installed package in `mod list --json`. `problem` is why the package is not used.
struct ModPackageEntry: Encodable, Equatable {
  let name: String
  let version: String?
  let author: String?
  let files: [String]
  let problem: String?

  init(_ package: ModPackage) {
    name = package.name
    version = package.manifest?.version
    author = package.manifest?.author
    files = package.manifest.map(listedFiles(of:)) ?? []
    problem = package.problem
  }
}
