import Foundation

extension RepositoryValidation {
  /// Applies the built-in patches under `patches` to the record files under `records` with
  /// ``ControllerPatchMerge`` and writes each effective record to the same relative path under
  /// `output`. Nothing is written when any problem is found.
  ///
  /// A record's members are written in the order of its file, then the members that patches add
  /// in the order of the patch that adds them, at every depth. An array or value that a patch
  /// replaces takes the order of the patch.
  ///
  /// A patch file must hold a valid ``ControllerPatch`` at the path its selector gives: the
  /// vendor directory for a `vendorID` with `productID`, the top of `patches` for the others. A
  /// patch file at any other path, such as one in a deeper directory, is refused. Record files
  /// are read at any depth and written at the same relative path. A patch that selects no
  /// record, and one that changes nothing in a record other than the `all` patch, are problems.
  package static func applyPatches(
    records: URL,
    patches: URL,
    output: URL
  ) -> [RepositoryProblem] {
    var problems: [RepositoryProblem] = []
    let patchFiles = readPatches(under: patches, problems: &problems)
    let recordFiles = readRecords(under: records, problems: &problems)
    var selected: Set<URL> = []
    var effective: [(file: RecordFile, document: [String: Any], order: OrderedJSON)] = []
    for file in recordFiles {
      var document = file.document
      var order = file.order
      let chosen = ControllerPatchMerge.ordered(
        patchFiles.filter { $0.patch.selector.selects(file.model) }
      ) { ($0.patch, nil) }
      for entry in chosen {
        selected.insert(entry.url)
        let merged = ControllerPatchMerge.apply(entry.patch, to: document)
        order = order.merging(patch: entry.order(appliedTo: document))
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
      effective.append((file, document, order))
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
      for (file, document, order) in effective {
        let destination = output.appendingPathComponent(file.relativePath)
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try OrderedJSON(foundation: document, order: order).formattedData()
          .write(to: destination, options: .atomic)
      }
    } catch {
      return [
        RepositoryProblem.fileAccess(output.path, error)
      ]
    }
    return []
  }

  private struct PatchFile {
    let url: URL
    let patch: ControllerPatch
    /// The members of the file's `patch` object in file order.
    let body: OrderedJSON

    /// The order that this patch adds to a record when it is applied to `document`: the body in
    /// file order, and for an `all` patch only the `tuning` keys that the record's family reads.
    func order(appliedTo document: [String: Any]) -> OrderedJSON {
      guard patch.selector == .all else { return body }
      let keys = Set(
        (ControllerPatchMerge.appliedBody(of: patch, to: document)?["tuning"] as? [String: Any])?
          .keys ?? [:].keys
      )
      guard case .object(let members) = body,
        case .object(let tuning)? = members.first(where: { $0.key == "tuning" })?.value
      else { return .object([]) }
      return .object([
        .init(key: "tuning", value: .object(tuning.filter { keys.contains($0.key) }))
      ])
    }
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
        let data = try RepositoryProblem.read(url)
        try ControllerRecordSet.requireUTF8(data)
        let document = try ControllerRecordSet.jsonObject(data)
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
  ) -> [PatchFile] {
    let urls: [URL]
    switch jsonFiles(under: directory) {
    case .failure(let problem):
      problems.append(problem)
      return []
    case .success(let found): urls = found
    }
    var patches: [PatchFile] = []
    for url in urls {
      do {
        let data = try RepositoryProblem.read(url)
        try ControllerRecordSet.requireUTF8(data)
        let order = try ControllerRecordSet.ordered(data)
        let document = try ControllerRecordSet.jsonObject(data)
        let patch = try ControllerPatch.parse(document, file: url.lastPathComponent)
        let expected = patchPath(of: patch.selector)
        guard relativePath(of: url, under: directory) == expected else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "the patch path must be \(expected)"
          )
        }
        guard case .object(let members) = order,
          let body = members.first(where: { $0.key == "patch" })?.value
        else { throw ControllerRecordProblem(code: .invalidControllerRecord, "not a JSON object") }
        patches.append(PatchFile(url: url, patch: patch, body: body))
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

  /// Whether `merged` differs from `document` as JSON values. The two are compared by the bytes
  /// of their sorted JSON text, which `JSONSerialization` writes from the parsed values, so
  /// numbers that read as the same value, such as `1` and `1.0`, are not a change, as `1 == 1.0`
  /// holds in the Python generator; the text of a number in a file is not compared.
  private static func isChanged(_ merged: [String: Any], from document: [String: Any]) -> Bool {
    let options: JSONSerialization.WritingOptions = .sortedKeys
    return (try? JSONSerialization.data(withJSONObject: merged, options: options))
      != (try? JSONSerialization.data(withJSONObject: document, options: options))
  }
}
