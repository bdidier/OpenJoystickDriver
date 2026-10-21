import Foundation

/// One line a followed log stream produced.
public struct ApplicationServiceLogLine: Equatable, Sendable {
  public let stream: ApplicationServiceLogStream
  public let text: String

  public init(stream: ApplicationServiceLogStream, text: String) {
    self.stream = stream
    self.text = text
  }
}

/// Polls a log file for appended lines.
public enum ApplicationServiceLogFollower {
  static let pollNanoseconds: UInt64 = 200_000_000

  /// The lines appended to the log of `stream` after `offset` bytes, until the task that
  /// iterates the stream is cancelled.
  public static func lines(
    of stream: ApplicationServiceLogStream,
    from offset: UInt64
  ) -> AsyncStream<ApplicationServiceLogLine> {
    AsyncStream { continuation in
      let task = Task {
        let url = ApplicationServiceLogService.url(for: stream)
        var position = offset
        var pending = Data()
        while !Task.isCancelled {
          if let chunk = readAppended(url, position: &position) {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
              let line = pending[pending.startIndex..<newline]
              continuation.yield(
                ApplicationServiceLogLine(
                  stream: stream,
                  text: String(bytes: line, encoding: .utf8) ?? ""
                )
              )
              pending.removeSubrange(pending.startIndex...newline)
            }
          }
          try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Reads what `url` gained after `position` and moves `position` to the end; a file that shrank
  /// belongs to a later session, so it is read from the start.
  private static func readAppended(_ url: URL, position: inout UInt64) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { handle.closeFile() }
    let size = handle.seekToEndOfFile()
    if size < position { position = 0 }
    guard size > position else { return nil }
    handle.seek(toFileOffset: position)
    let data = handle.readData(ofLength: Int(size - position))
    position += UInt64(data.count)
    return data
  }
}
