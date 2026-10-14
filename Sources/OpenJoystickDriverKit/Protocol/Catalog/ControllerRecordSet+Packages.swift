import Foundation

/// The bundled records with the records of the installed packages applied, and the package files.
struct ControllerPackageRecords {
  var records: [ControllerModelID: ControllerRecord]
  var files: [ControllerRecordFile] = []

  /// Lists the package file of `model` as skipped, because the user's file `url` replaces it.
  mutating func overridden(_ model: ControllerModelID, by url: URL) {
    files = files.map { file in
      guard file.model == model, file.problem == nil else { return file }
      return ControllerRecordFile(
        url: file.url,
        model: model,
        operation: file.operation,
        problem: "replaced by your file \(url.lastPathComponent)"
      )
    }
  }
}

extension ControllerRecordSet {
  /// The records of the packages in `directory`, in package-name order. A package that cannot be
  /// used, such as one whose `requires` leaves out the running version, is skipped and its
  /// `mod.json` is listed with the reason. A package record that fails validation, has the wrong
  /// file name, or repeats the model of an earlier package's record is skipped and listed with
  /// its reason. `runningVersion` is the OJD version that the
  /// `requires` of a package is checked against; nil means the running one.
  static func packageRecords(
    in directory: URL,
    runningVersion: String? = nil
  ) -> ControllerPackageRecords {
    var packaged = ControllerPackageRecords(records: bundled.records)
    var owners: [ControllerModelID: String] = [:]
    for package in ModPackageStore(directory: directory, runningVersion: runningVersion).list() {
      guard let manifest = package.manifest, package.problem == nil else {
        packaged.files.append(
          ControllerRecordFile(
            url: package.directory.appendingPathComponent(ModPackageManifest.fileName),
            model: nil,
            operation: nil,
            problem: package.problem
          )
        )
        continue
      }
      for name in manifest.records.sorted() {
        let url = package.directory.appendingPathComponent("Controllers/\(name)")
        let file: ControllerRecordFile
        do {
          let validated = try validate(Data(contentsOf: url), file: url, layer: .package)
          let model = validated.record.model
          if name != fileName(for: model) {
            throw ControllerRecordProblem("the file name must be \(fileName(for: model))")
          }
          if let owner = owners[model] {
            throw ControllerRecordProblem("same controller as package \(owner)")
          }
          owners[model] = package.name
          packaged.records[model] = validated.record
          file = ControllerRecordFile(
            url: url,
            model: model,
            operation: validated.operation,
            problem: nil
          )
        } catch {
          file = ControllerRecordFile(
            url: url,
            model: nil,
            operation: nil,
            problem: problemDescription(error)
          )
        }
        packaged.files.append(file)
      }
    }
    return packaged
  }
}
