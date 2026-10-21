import Foundation
import OpenJoystickDriverKit

/// A call that the tool refuses. It exits with ``exitCode``, which no check result uses, and names
/// the call on standard error.
private struct UsageError: Error {
  static let exitCode: Int32 = 64
  let message: String
}

private let usage = """
  usage:
    OJDRepositoryTool validate records <directory>
    OJDRepositoryTool validate descriptions <directory>
    OJDRepositoryTool validate profiles <path>...
    OJDRepositoryTool validate personas <path>...
    OJDRepositoryTool apply-patches --records <directory> --patches <directory> --out <directory>
  A path is a file, or a directory whose .json files are checked.
  Each problem is one JSON line {"code", "file", "message"} on standard output. The exit status is
  0 without a problem, 1 with one, and 64 for a call that the tool refuses.
  """

private func directory(_ path: String) throws -> URL {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
    isDirectory.boolValue
  else { throw UsageError(message: "\(path) is not a directory") }
  return URL(fileURLWithPath: path, isDirectory: true)
}

/// The files that `paths` name, in the order given; a directory stands for its `.json` files in
/// file-name order.
private func files(_ paths: [String]) throws -> [URL] {
  guard !paths.isEmpty else { throw UsageError(message: "no path given") }
  return try paths.flatMap { path -> [URL] in
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      throw UsageError(message: "\(path) does not exist")
    }
    guard isDirectory.boolValue else { return [URL(fileURLWithPath: path)] }
    return try FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: path, isDirectory: true),
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}

private func options(_ arguments: [String], names: [String]) throws -> [String: String] {
  var values: [String: String] = [:]
  var index = 0
  while index < arguments.count {
    let name = arguments[index]
    guard names.contains(name) else { throw UsageError(message: "unknown option \(name)") }
    guard index + 1 < arguments.count else { throw UsageError(message: "\(name) needs a value") }
    guard values[name] == nil else { throw UsageError(message: "\(name) is given twice") }
    values[name] = arguments[index + 1]
    index += 2
  }
  for name in names where values[name] == nil {
    throw UsageError(message: "\(name) is required")
  }
  return values
}

private func run(_ arguments: [String]) throws -> [RepositoryProblem] {
  guard let command = arguments.first else { throw UsageError(message: "no subcommand given") }
  let rest = Array(arguments.dropFirst())
  switch command {
  case "validate":
    guard let kind = rest.first else { throw UsageError(message: "validate needs a kind") }
    let paths = Array(rest.dropFirst())
    switch kind {
    case "records", "descriptions":
      guard paths.count == 1, let path = paths.first else {
        throw UsageError(message: "validate \(kind) takes one directory")
      }
      let root = try directory(path)
      return kind == "records"
        ? RepositoryValidation.records(in: root) : RepositoryValidation.descriptions(in: root)
    case "profiles": return try files(paths).compactMap(RepositoryValidation.profile(at:))
    case "personas": return try files(paths).compactMap(RepositoryValidation.persona(at:))
    default: throw UsageError(message: "unknown validate kind \(kind)")
    }
  case "apply-patches":
    let values = try options(rest, names: ["--records", "--patches", "--out"])
    return RepositoryValidation.applyPatches(
      records: try directory(values["--records"] ?? ""),
      patches: try directory(values["--patches"] ?? ""),
      output: URL(fileURLWithPath: values["--out"] ?? "", isDirectory: true)
    )
  default: throw UsageError(message: "unknown subcommand \(command)")
  }
}

private func line(_ problem: RepositoryProblem) throws -> Data {
  let object: [String: Any] = [
    "file": problem.file, "code": problem.code?.rawValue ?? NSNull(), "message": problem.message,
  ]
  return try JSONSerialization.data(
    withJSONObject: object,
    options: [.sortedKeys, .withoutEscapingSlashes]
  ) + Data("\n".utf8)
}

do {
  let problems = try run(Array(CommandLine.arguments.dropFirst()))
  for problem in problems { FileHandle.standardOutput.write(try line(problem)) }
  exit(problems.isEmpty ? 0 : 1)
} catch let error as UsageError {
  FileHandle.standardError.write(Data("OJDRepositoryTool: \(error.message)\n\(usage)\n".utf8))
  exit(UsageError.exitCode)
}
