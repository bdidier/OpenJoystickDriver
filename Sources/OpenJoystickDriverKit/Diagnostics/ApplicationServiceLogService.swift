import Darwin
import Foundation

public enum ApplicationServiceLogStream: String, CaseIterable, Codable, Sendable {
  case standardOutput = "StandardOutput"
  case standardError = "StandardError"
}

public struct ApplicationServiceLogSnapshot: Codable, Equatable, Sendable {
  public let stream: ApplicationServiceLogStream
  public let path: String
  public let exists: Bool
  public let fileSizeBytes: UInt64
  public let lines: [String]
  public let truncated: Bool

  public init(
    stream: ApplicationServiceLogStream,
    path: String,
    exists: Bool,
    fileSizeBytes: UInt64,
    lines: [String],
    truncated: Bool
  ) {
    self.stream = stream
    self.path = path
    self.exists = exists
    self.fileSizeBytes = fileSizeBytes
    self.lines = lines
    self.truncated = truncated
  }
}

public enum ApplicationServiceLogService {
  public static let defaultMaximumLines = 100
  public static let defaultMaximumBytes = 262_144
  /// The accepted range of a requested line count.
  public static let linesRange = 1...10_000
  /// The line count of `ojd log export` and of the Save Activity Log menu item.
  public static let defaultExportLines = 2_000
  /// The note to read before sharing a log.
  public static var sharingWarning: String { Localization().string("cli.log.sharing_warning") }

  /// The folder that holds the log files, which `ojd log path` prints.
  public static var directory: URL {
    url(for: .standardOutput).deletingLastPathComponent()
  }

  public static func url(
    for stream: ApplicationServiceLogStream,
    dataDirectory: any DataDirectory = MacOSDataDirectory()
  ) -> URL {
    let suffix = stream == .standardOutput ? "out" : "err"
    return dataDirectory.fileURL("OpenJoystickDriver.\(suffix).log", in: .logs)
  }

  /// Redirects the host process streams to fresh, user-private files for this session.
  ///
  /// Headless commands deliberately do not call this function so their output remains
  /// attached to the invoking terminal.
  public static func beginCurrentSessionCapture() throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    for (stream, target) in [
      (ApplicationServiceLogStream.standardOutput, STDOUT_FILENO),
      (ApplicationServiceLogStream.standardError, STDERR_FILENO),
    ] {
      let path = url(for: stream).path
      let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else {
        throw ApplicationServiceLogError("Could not open \(path): errno \(errno).")
      }
      guard dup2(descriptor, target) >= 0 else {
        let code = errno
        Darwin.close(descriptor)
        throw ApplicationServiceLogError("Could not redirect \(path): errno \(code).")
      }
      Darwin.close(descriptor)
    }
    setvbuf(stdout, nil, _IOLBF, 0)
    setvbuf(stderr, nil, _IOLBF, 0)
  }

  public static func tail(
    stream: ApplicationServiceLogStream,
    maximumLines: Int = defaultMaximumLines,
    maximumBytes: Int = defaultMaximumBytes
  ) throws -> ApplicationServiceLogSnapshot {
    try tail(
      url: url(for: stream),
      stream: stream,
      maximumLines: maximumLines,
      maximumBytes: maximumBytes
    )
  }

  static func tail(
    url: URL,
    stream: ApplicationServiceLogStream,
    maximumLines: Int,
    maximumBytes: Int
  ) throws -> ApplicationServiceLogSnapshot {
    guard maximumLines > 0 else {
      throw ApplicationServiceLogError("maximumLines must be greater than zero.")
    }
    guard maximumBytes > 0 else {
      throw ApplicationServiceLogError("maximumBytes must be greater than zero.")
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      return ApplicationServiceLogSnapshot(
        stream: stream,
        path: url.path,
        exists: false,
        fileSizeBytes: 0,
        lines: [],
        truncated: false
      )
    }

    let handle = try FileHandle(forReadingFrom: url)
    defer { handle.closeFile() }
    let fileSize = handle.seekToEndOfFile()
    let retainedBytes = min(fileSize, UInt64(maximumBytes))
    let offset = fileSize - retainedBytes
    handle.seek(toFileOffset: offset)
    let data = handle.readDataToEndOfFile()
    var text = String(bytes: data, encoding: .utf8) ?? ""

    if offset > 0 {
      if let firstNewline = text.firstIndex(of: "\n") {
        text.removeSubrange(...firstNewline)
      } else {
        text = ""
      }
    }

    let allLines = text.split(whereSeparator: \.isNewline).map(String.init)
    let selectedLines = Array(allLines.suffix(maximumLines))
    return ApplicationServiceLogSnapshot(
      stream: stream,
      path: url.path,
      exists: true,
      fileSizeBytes: fileSize,
      lines: selectedLines,
      truncated: offset > 0 || selectedLines.count < allLines.count
    )
  }

  /// The text `ojd log show` prints on a terminal and `ojd log export` writes: one heading per
  /// stream, a note for a missing, empty or shortened log, then its lines.
  public static func humanText(_ snapshots: [ApplicationServiceLogSnapshot]) -> String {
    let localization = Localization()
    var text = ""
    for snapshot in snapshots {
      text += "== \(CommandLineName.kebab(snapshot.stream.rawValue)): \(snapshot.path) ==\n"
      if !snapshot.exists {
        text += localization.string("cli.log.show.missing") + "\n"
      } else if snapshot.lines.isEmpty {
        text += localization.string("cli.log.show.empty") + "\n"
      }
      if snapshot.truncated {
        text += localization.string("cli.log.show.truncated") + "\n"
      }
      for line in snapshot.lines { text += line + "\n" }
    }
    return text
  }

  /// The file content of `ojd log export`: ``humanText(_:)`` with `home` written as `~`.
  public static func exportText(
    _ snapshots: [ApplicationServiceLogSnapshot],
    home: String
  ) -> String {
    redactingHome(humanText(snapshots), home: home)
  }

  /// `text` with each path under `home` written as `~`, as the support report leaves out
  /// filesystem paths. A longer folder name that starts with `home` is left alone.
  public static func redactingHome(_ text: String, home: String) -> String {
    let home = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard !home.isEmpty,
      let expression = try? NSRegularExpression(
        pattern: NSRegularExpression.escapedPattern(for: home) + #"(?=$|[/\s"':,;)\]])"#,
        options: .anchorsMatchLines
      )
    else { return text }
    return expression.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: "~"
    )
  }
}

private struct ApplicationServiceLogError: LocalizedError, Sendable {
  let message: String

  init(_ message: String) { self.message = message }

  var errorDescription: String? { message }
}
