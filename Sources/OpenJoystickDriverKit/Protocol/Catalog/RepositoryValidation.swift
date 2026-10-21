import Foundation

/// One file that fails a check of a repository tool, and why.
public struct RepositoryProblem: Error, Equatable, Sendable {
  /// The path of the file, or the name of a file that is absent.
  public let file: String
  /// The catalog code of the failed rule; nil for a file that cannot be read and for a persona
  /// rule, which the persona loader reports without a code.
  public let code: ErrorCode?
  /// The reason, without the code.
  public let message: String

  public init(file: String, code: ErrorCode?, message: String) {
    self.file = file
    self.code = code
    self.message = message
  }

  /// The problem that `error` reports for `file`, with the code that
  /// ``ControllerRecordSet/problemCode(_:)`` gives and the reason that
  /// ``ControllerRecordSet/problemDescription(_:includingCode:document:)`` gives for a `document`
  /// of that kind.
  init(file: String, error: any Error, document: String) {
    self.init(
      file: file,
      code: ControllerRecordSet.problemCode(error),
      message: ControllerRecordSet.problemDescription(
        error,
        includingCode: false,
        document: document
      )
    )
  }
}

/// The checks that the repository tool runs over files outside the bundle. Each check is the one
/// the bundled files and the user's files pass, applied to the files it is given.
public enum RepositoryValidation {
  /// The problems of the Controller files under `directory`, found recursively, by
  /// ``ControllerRecordSet``: each file's record rules, the file name its record needs, and an
  /// identity that is not held twice.
  public static func records(in directory: URL) -> [RepositoryProblem] {
    switch jsonFiles(under: directory) {
    case .failure(let problem): return [problem]
    case .success(let urls):
      guard !urls.isEmpty else {
        return [
          RepositoryProblem(
            file: directory.path,
            code: .invalidControllerRecord,
            message: "controller catalog is empty"
          )
        ]
      }
      return ControllerRecordSet.loadCatalog(urls).problems
    }
  }

  /// The problems of the protocol descriptions under `directory`: each file's own rules, the
  /// family its file name must name, and a family without a file.
  public static func descriptions(in directory: URL) -> [RepositoryProblem] {
    switch jsonFiles(under: directory) {
    case .failure(let problem): return [problem]
    case .success(let urls):
      return ProtocolDescription.loadCatalog(urls, missing: directory.path).problems
    }
  }

  /// The problem of the remapping profile file `url`, or nil when ``RemappingProfileFileStore``
  /// loads it.
  public static func profile(at url: URL) -> RepositoryProblem? {
    do { _ = try RemappingProfileFileStore.load(from: url) } catch {
      return RepositoryProblem(
        file: url.path,
        code: RemappingProfileFileStore.problemCode(error),
        message: ControllerRecordSet.problemDescription(
          error,
          includingCode: false,
          document: "profile"
        )
      )
    }
    return nil
  }

  /// The problem of the persona file `url`, or nil when ``VirtualHIDProfileOverrideStore`` reads
  /// it.
  public static func persona(at url: URL) -> RepositoryProblem? {
    do { _ = try VirtualHIDProfileOverrideStore.parse(Data(contentsOf: url)) } catch {
      return RepositoryProblem(file: url.path, error: error, document: "persona")
    }
    return nil
  }

  /// The `.json` files under `directory`, found recursively, in path order.
  static func jsonFiles(under directory: URL) -> Result<[URL], RepositoryProblem> {
    guard
      let walker = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else {
      return .failure(
        RepositoryProblem(file: directory.path, code: nil, message: "cannot read the directory")
      )
    }
    let urls = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
    return .success(urls.sorted { $0.path < $1.path })
  }
}
