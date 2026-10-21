import Foundation

extension RepositoryValidation {
  /// Applies the built-in patches under `patches` to the record files under `records` with
  /// ``ControllerPatchMerge`` and writes each effective record to the same relative path under
  /// `output`, in the member order of its file. Nothing is written when any problem is found.
  ///
  /// A patch file must hold a valid ``ControllerPatch`` at the path its selector gives: the
  /// vendor directory for a `vendorID` with `productID`, the top of `patches` for the others.
  /// A patch that selects no record, and one that changes nothing in a record other than the
  /// `all` patch, are problems.
  public static func applyPatches(
    records: URL,
    patches: URL,
    output: URL
  ) -> [RepositoryProblem] {
    var problems: [RepositoryProblem] = []
    let patchFiles = readPatches(under: patches, problems: &problems)
    let recordFiles = readRecords(under: records, problems: &problems)
    var selected: Set<URL> = []
    var effective: [(file: RecordFile, document: [String: Any])] = []
    for file in recordFiles {
      var document = file.document
      let chosen = ControllerPatchMerge.ordered(
        patchFiles.filter { $0.patch.selector.selects(file.model) }
      ) { ($0.patch, nil) }
      for entry in chosen {
        selected.insert(entry.url)
        let merged = ControllerPatchMerge.apply(entry.patch, to: document)
        if entry.patch.selector != .all, !isChanged(merged, from: document) {
          problems.append(
            RepositoryProblem(
              file: entry.url.path,
              code: .invalidControllerRecord,
              message: "the patch changes nothing in \(file.model)"
            )
          )
        }
        document = merged
      }
      effective.append((file, document))
    }
    for entry in patchFiles where entry.patch.selector != .all && !selected.contains(entry.url) {
      problems.append(
        RepositoryProblem(
          file: entry.url.path,
          code: .invalidControllerRecord,
          message: "\(entry.patch.selector.description) is not a known controller"
        )
      )
    }
    guard problems.isEmpty else { return problems }
    do {
      for (file, document) in effective {
        let destination = output.appendingPathComponent(file.relativePath)
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try OrderedJSON(foundation: document, order: file.order).formattedData()
          .write(to: destination, options: .atomic)
      }
    } catch {
      return [
        RepositoryProblem(file: output.path, code: nil, message: error.localizedDescription)
      ]
    }
    return []
  }

  private struct RecordFile {
    let relativePath: String
    let model: ControllerModelID
    let document: [String: Any]
    let order: OrderedJSON
  }

  private static func readRecords(
    under directory: URL,
    problems: inout [RepositoryProblem]
  ) -> [RecordFile] {
    let urls: [URL]
    switch jsonFiles(under: directory) {
    case .failure(let problem):
      problems.append(problem)
      return []
    case .success(let found): urls = found
    }
    var files: [RecordFile] = []
    for url in urls {
      do {
        let data = try Data(contentsOf: url)
        try ControllerRecordSet.requireUTF8(data)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ControllerRecordProblem(code: .invalidControllerRecord, "not a JSON object") }
        guard
          let vendorID = ControllerPatch.strictInteger(document["vendorID"]).flatMap(
            UInt16.init(exactly:)
          ),
          let productID = ControllerPatch.strictInteger(document["productID"]).flatMap(
            UInt16.init(exactly:)
          )
        else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "vendorID must be 1...65535 and productID 0...65535"
          )
        }
        files.append(
          RecordFile(
            relativePath: relativePath(of: url, under: directory),
            model: ControllerModelID(vendorID: vendorID, productID: productID),
            document: document,
            order: try ControllerRecordSet.ordered(data)
          )
        )
      } catch {
        problems.append(RepositoryProblem(file: url.path, error: error, document: "record"))
      }
    }
    return files
  }

  private static func readPatches(
    under directory: URL,
    problems: inout [RepositoryProblem]
  ) -> [(url: URL, patch: ControllerPatch)] {
    let urls: [URL]
    switch jsonFiles(under: directory) {
    case .failure(let problem):
      problems.append(problem)
      return []
    case .success(let found): urls = found
    }
    var patches: [(url: URL, patch: ControllerPatch)] = []
    for url in urls {
      do {
        let data = try Data(contentsOf: url)
        try ControllerRecordSet.requireUTF8(data)
        _ = try ControllerRecordSet.ordered(data)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ControllerRecordProblem(code: .invalidControllerRecord, "not a JSON object") }
        let patch = try ControllerPatch.parse(document, file: url.lastPathComponent)
        let expected = patchPath(of: patch.selector)
        guard relativePath(of: url, under: directory) == expected else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "the patch path must be \(expected)"
          )
        }
        patches.append((url, patch))
      } catch {
        problems.append(RepositoryProblem(file: url.path, error: error, document: "patch"))
      }
    }
    return patches
  }

  /// Where a built-in patch with `selector` is stored under the patch directory.
  private static func patchPath(of selector: ControllerPatch.Selector) -> String {
    guard case .identity(let model) = selector else { return selector.fileName }
    return String(format: "%04x/", model.vendorID) + selector.fileName
  }

  private static func relativePath(of url: URL, under directory: URL) -> String {
    let root = directory.standardizedFileURL.pathComponents
    return url.standardizedFileURL.pathComponents.dropFirst(root.count).joined(separator: "/")
  }

  private static func isChanged(_ merged: [String: Any], from document: [String: Any]) -> Bool {
    let options: JSONSerialization.WritingOptions = .sortedKeys
    return (try? JSONSerialization.data(withJSONObject: merged, options: options))
      != (try? JSONSerialization.data(withJSONObject: document, options: options))
  }
}
