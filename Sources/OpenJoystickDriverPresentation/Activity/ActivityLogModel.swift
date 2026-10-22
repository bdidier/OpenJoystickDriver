#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// One line of a service log, with the stream it came from.
  struct ActivityLogEntry: Identifiable, Equatable {
    let id: Int
    let stream: ApplicationServiceLogStream
    let text: String
  }

  /// Which streams the Activity log table shows: the segments of the toolbar's filter.
  enum ActivityLogFilter: Int, CaseIterable {
    case all
    case output
    case errors

    var titleKey: String {
      switch self {
      case .all: return "ui.console.all"
      case .output: return "ui.console.output"
      case .errors: return "ui.console.errors"
      }
    }

    func includes(_ stream: ApplicationServiceLogStream) -> Bool {
      switch self {
      case .all: return true
      case .output: return stream == .standardOutput
      case .errors: return stream == .standardError
      }
    }

    /// The entries of the shown streams that contain `search`, ignoring case and diacritics. A
    /// blank search keeps every entry.
    func rows(in entries: [ActivityLogEntry], matching search: String) -> [ActivityLogEntry] {
      let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
      return entries.filter { entry in
        includes(entry.stream)
          && (query.isEmpty || entry.text.localizedStandardContains(query))
      }
    }
  }

  extension ApplicationServiceLogStream {
    var activityTitleKey: String {
      switch self {
      case .standardOutput: return "ui.console.output"
      case .standardError: return "ui.console.errors"
      }
    }
  }

  /// The line counts that the toolbar offers. The service accepts 1 to 10000 lines.
  enum ActivityLogLineCount {
    static let choices = [100, 500, 1_000, 2_000, 5_000, 10_000]
    static let initial = 500
  }

  /// Reads the service logs; tests replace it.
  struct ActivityLogSource: Sendable {
    var tail: @Sendable (ApplicationServiceLogStream, Int) throws -> ApplicationServiceLogSnapshot
    var follow:
      @Sendable (ApplicationServiceLogStream, UInt64) -> AsyncStream<ApplicationServiceLogLine>

    static let system = Self(
      tail: { stream, lines in
        try ApplicationServiceLogService.tail(stream: stream, maximumLines: lines)
      },
      follow: { stream, offset in ApplicationServiceLogFollower.lines(of: stream, from: offset) }
    )
  }

  /// The Activity log: the end of both service logs, followed live while the log is shown.
  @MainActor
  final class ActivityLogModel: ObservableObject {
    /// Entries kept while following; older ones drop out in batches of a tenth.
    static let retainedEntries = 2 * ApplicationServiceLogService.linesRange.upperBound

    @Published
    var filter: ActivityLogFilter = .all {
      didSet { refreshRows() }
    }
    @Published
    var searchText = "" {
      didSet { refreshRows() }
    }
    @Published
    private(set) var lineCount = ActivityLogLineCount.initial
    /// The shown entries, newest first. A SwiftUI `Table` cannot scroll to its last row, so the
    /// log keeps the newest line visible at the top instead of pinning the bottom as Console does.
    /// Stored, and changed only by the filter, the search, a reload or an appended line.
    @Published
    private(set) var rows: [ActivityLogEntry] = []
    /// Why the logs could not be read.
    @Published
    private(set) var loadFailure: String?

    private(set) var entries: [ActivityLogEntry] = []
    private(set) var isFollowing = false
    private let retainedEntries: Int
    private let source: ActivityLogSource
    private var followTasks: [Task<Void, Never>] = []
    private var nextID = 0

    init(
      source: ActivityLogSource = .system,
      retainedEntries: Int = ActivityLogModel.retainedEntries
    ) {
      self.source = source
      self.retainedEntries = retainedEntries
    }

    /// The shown lines in the order they were written, one per line.
    var copyText: String { rows.reversed().map(\.text).joined(separator: "\n") }

    /// Starts following when the log is shown and stops when it is not.
    func setFollowing(_ shouldFollow: Bool) {
      if shouldFollow {
        if !isFollowing { start() }
      } else {
        stop()
      }
    }

    /// Reads the end of both logs and follows what they gain.
    func start() {
      stop()
      isFollowing = true
      let snapshots: [ApplicationServiceLogSnapshot]
      do {
        snapshots = try ApplicationServiceLogStream.allCases.map {
          try source.tail($0, lineCount)
        }
      } catch {
        loadFailure = error.localizedDescription
        entries = []
        refreshRows()
        return
      }
      loadFailure = nil
      nextID = 0
      entries = snapshots.flatMap { snapshot in snapshot.lines.map { entry(snapshot.stream, $0) } }
      refreshRows()
      for snapshot in snapshots {
        let lines = source.follow(snapshot.stream, snapshot.fileSizeBytes)
        followTasks.append(
          Task { [weak self] in
            for await line in lines { self?.append(line) }
          }
        )
      }
    }

    func stop() {
      followTasks.forEach { $0.cancel() }
      followTasks = []
      isFollowing = false
    }

    func setLineCount(_ count: Int) {
      lineCount = count
      start()
    }

    func copyVisible() {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(copyText, forType: .string)
    }

    /// Opens the folder that `ojd log path` prints; false when it did not open.
    func showInFinder() -> Bool { NSWorkspace.shared.open(ApplicationServiceLogService.directory) }

    private func entry(_ stream: ApplicationServiceLogStream, _ text: String) -> ActivityLogEntry {
      defer { nextID += 1 }
      return ActivityLogEntry(id: nextID, stream: stream, text: text)
    }

    private func refreshRows() {
      rows = filter.rows(in: entries, matching: searchText).reversed()
    }

    /// Adds a line the follower produced. Only a line the filter and search show joins `rows`;
    /// the oldest entries drop out once a tenth more than the retained count piled up.
    func append(_ line: ApplicationServiceLogLine) {
      let added = entry(line.stream, line.text)
      entries.append(added)
      if entries.count > retainedEntries + retainedEntries / 10 {
        entries.removeFirst(entries.count - retainedEntries)
        refreshRows()
      } else if !filter.rows(in: [added], matching: searchText).isEmpty {
        rows.insert(added, at: 0)
      }
    }
  }

#endif
