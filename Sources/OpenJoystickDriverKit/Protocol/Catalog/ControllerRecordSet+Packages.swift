import Foundation

/// The bundled records with the records of the installed packages applied, and the package files.
struct ControllerPackageRecords {
  var records: [ControllerIdentity: ControllerRecord]
  var files: [ControllerRecordFile] = []

  /// Lists the package file of `identity` as skipped, because the user's file `url` replaces it.
  mutating func overridden(_ identity: ControllerIdentity, by url: URL) {
    files = files.map { file in
      guard file.identity == identity, file.problem == nil else { return file }
      return ControllerRecordFile(
        url: file.url,
        identity: identity,
        operation: file.operation,
        problem: "replaced by your file \(url.lastPathComponent)"
      )
    }
  }
}

extension ControllerRecordSet {
  /// The records of the packages in `directory`, in package-name order. A package record that
  /// fails validation, has the wrong file name, or repeats the identity of an earlier package's
  /// record is skipped and listed with its reason.
  static func packageRecords(in directory: URL) -> ControllerPackageRecords {
    var packaged = ControllerPackageRecords(records: bundled.records)
    var owners: [ControllerIdentity: String] = [:]
    for package in ModPackageStore(directory: directory).list() {
      guard let manifest = package.manifest else {
        packaged.files.append(
          ControllerRecordFile(
            url: package.directory.appendingPathComponent(ModPackageManifest.fileName),
            identity: nil,
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
          let identity = validated.record.identity
          if name != fileName(for: identity) {
            throw ControllerRecordProblem("the file name must be \(fileName(for: identity))")
          }
          if let owner = owners[identity] {
            throw ControllerRecordProblem("same controller as package \(owner)")
          }
          owners[identity] = package.name
          packaged.records[identity] = validated.record
          file = ControllerRecordFile(
            url: url,
            identity: identity,
            operation: validated.operation,
            problem: nil
          )
        } catch {
          file = ControllerRecordFile(
            url: url,
            identity: nil,
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
