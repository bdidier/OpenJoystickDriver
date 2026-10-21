import Darwin
import Dispatch
import Foundation
import OpenJoystickDriverKit

enum CLIOutput {
  static func stdout(_ message: String = "", terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardOutput)
  }

  static func stderr(_ message: String = "", terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardError)
  }

  /// Prints a success message on stderr unless `--quiet` is set.
  static func success(_ message: String) {
    guard !CLIContext.current.quiet else { return }
    stderr(message)
  }

  /// The `apiVersion` of every `--json` document and stream line.
  static let apiVersion = OpenJoystickDriverAPI.version

  /// The `kind` of the running command's `--json` output; see ``CLI/outputKinds``.
  @TaskLocal
  static var kind = ""

  /// Prints `value` as a JSON document on stdout, with `apiVersion` and `kind`, laid out by
  /// ``OrderedJSON/formatted()`` like the bundled record files.
  ///
  /// The members of the envelope and of a Swift value are sorted by name. An embedded
  /// ``OrderedJSON`` keeps its member order and the text of its numbers.
  ///
  /// `kind` replaces the running command's kind for a command whose output kind depends on its
  /// options.
  static func json(_ value: some Encodable, kind: String? = nil) throws {
    let document = try OrderedJSONEncoder().encode(
      CLIDocument(kind: kind ?? self.kind, value: value)
    )
    stdout(document.formatted(), terminator: "")
  }

  /// Prints `value` as one line of JSON on stdout, with `apiVersion` and `kind`, for a `--json`
  /// stream. Members are sorted by name.
  static func jsonLine(_ value: some Encodable, kind: String? = nil) throws {
    let document = try OrderedJSONEncoder().encode(
      CLIDocument(kind: kind ?? self.kind, value: value)
    )
    stdout(document.compact())
  }

  /// Prints `value` as one line of JSON on stdout, without `apiVersion` and `kind`, such as a
  /// watch line `{type, object}`. Members are sorted by name.
  static func jsonLineWithoutEnvelope(_ value: some Encodable) throws {
    stdout(try OrderedJSONEncoder().encode(value).compact())
  }

  /// Prints one tab-separated record per row on stdout, for `--plain`. A tab or a newline character
  /// (line feed, carriage return, NEL, line and paragraph separators) inside a field becomes a
  /// space, so a field never splits a row or a record.
  static func plain(_ rows: [[String]]) {
    for row in rows {
      let fields = row.map { field in
        String(
          String.UnicodeScalarView(
            field.unicodeScalars.map { scalar in
              scalar == "\t" || Character(scalar).isNewline ? " " : scalar
            }
          )
        )
      }
      stdout(fields.joined(separator: "\t"))
    }
  }

  /// Collects output instead of writing it, for tests.
  @TaskLocal
  static var capture: CLIOutputCapture?

  private static func write(_ message: String, terminator: String, to handle: FileHandle) {
    let text = message + terminator
    if let capture {
      capture.append(text, toStandardError: handle === FileHandle.standardError)
      return
    }
    handle.write(Data(text.utf8))
  }
}

/// The `--json` result of a list command, as a Kubernetes list: the listed `items`, and the data
/// about the list in `metadata`.
struct CLIList<Item: Encodable, Metadata: Encodable>: Encodable {
  let metadata: Metadata
  let items: [Item]
}

/// The `metadata` of a list that has no data besides its items.
struct CLINoMetadata: Encodable {}

extension CLIList where Metadata == CLINoMetadata {
  init(items: [Item]) { self.init(metadata: CLINoMetadata(), items: items) }
}

/// A `--json` document: the keys of `value`, an object, with `apiVersion` and `kind` added.
private struct CLIDocument<Value: Encodable>: Encodable {
  let kind: String
  let value: Value

  private enum CodingKeys: String, CodingKey {
    case apiVersion
    case kind
  }

  func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(CLIOutput.apiVersion, forKey: .apiVersion)
    try container.encode(kind, forKey: .kind)
  }
}

final class CLIOutputCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var standardOutputText = ""
  private var standardErrorText = ""

  var standardOutput: String { lock.withLock { standardOutputText } }

  var standardError: String { lock.withLock { standardErrorText } }

  func append(_ text: String, toStandardError: Bool) {
    lock.withLock {
      if toStandardError { standardErrorText += text } else { standardOutputText += text }
    }
  }
}

private let cliShutdownCleanup = Locked<(@Sendable () async -> Void)?>(nil)
private let cliShutdownSources = Locked<[DispatchSourceSignal]>([])

func installCLIShutdownHandlers() {
  guard cliShutdownSources.withLock({ $0.isEmpty }) else { return }
  for signalNumber in [SIGINT, SIGTERM] {
    let source = DispatchSource.makeSignalSource(
      signal: signalNumber,
      queue: DispatchQueue.global(qos: .userInitiated)
    )
    source.setEventHandler {
      Task {
        let cleanup = cliShutdownCleanup.withLock { $0 }
        await cleanup?()
        fflush(stdout)
        fflush(stderr)
        exit(128 + signalNumber)
      }
    }
    source.resume()
    signal(signalNumber, SIG_IGN)
    cliShutdownSources.withLock { $0.append(source) }
  }
}

func withCLIShutdownCleanup<T>(
  _ cleanup: @escaping @Sendable () async -> Void,
  _ body: () async throws -> T
) async rethrows -> T {
  let previous = cliShutdownCleanup.withLock { current in
    defer { current = cleanup }
    return current
  }
  defer { cliShutdownCleanup.withLock { $0 = previous } }
  return try await body()
}
