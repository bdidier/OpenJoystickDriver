import Foundation

/// Reads and writes the equivalence snapshots in `Tests/EquivalenceSnapshots`.
///
/// A snapshot is a text file of sections, each starting with a `## <record>` line, so a
/// comparison can name the records that changed. Modes, chosen by environment variable:
/// - default: compare the rendered text with the file and report a mismatch;
/// - `OJD_SNAPSHOT_WRITE=1`: rewrite the file from the current tree;
/// - `OJD_SNAPSHOT_ACTUAL_DIR=<dir>`: write the rendered text to `<dir>` and never fail, so
///   `./Scripts/ojd snapshots check` can print the per-record diff.
package enum EquivalenceSnapshotStore {
  package static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // OpenJoystickDriverTestSupport
    .deletingLastPathComponent()  // Tests
    .appendingPathComponent("EquivalenceSnapshots", isDirectory: true)

  /// Renders sections as `## title` followed by their lines, sorted by title.
  package static func render(_ sections: [(title: String, lines: [String])]) -> String {
    sections.sorted { $0.title < $1.title }
      .map { "## \($0.title)\n" + $0.lines.map { $0 + "\n" }.joined() }
      .joined(separator: "\n")
  }

  /// Returns nil when the snapshot matches or was written; otherwise a message for the failure.
  package static func verify(_ rendered: String, named name: String) throws -> String? {
    let environment = ProcessInfo.processInfo.environment
    let file = directory.appendingPathComponent(name)
    if let actual = environment["OJD_SNAPSHOT_ACTUAL_DIR"] {
      let target = URL(fileURLWithPath: actual, isDirectory: true)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      try Data(rendered.utf8).write(to: target.appendingPathComponent(name))
      return nil
    }
    if environment["OJD_SNAPSHOT_WRITE"] == "1" {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data(rendered.utf8).write(to: file)
      return nil
    }
    guard let expected = try? String(contentsOf: file, encoding: .utf8) else {
      return "\(name) is missing; run ./Scripts/ojd snapshots write"
    }
    return expected == rendered
      ? nil : "\(name) differs from the tree; run ./Scripts/ojd snapshots check for the diff"
  }
}
