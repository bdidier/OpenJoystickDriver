import Foundation
import Testing

/// Lists the controls in the app sources that VoiceOver cannot name. The list must stay empty.
/// The sources under `controllersAreaFollowUp` are not scanned yet.
@Suite
struct AccessibilityAuditTests {
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Accessibility
    .deletingLastPathComponent()  // OpenJoystickDriverPresentationTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()

  private static let scannedDirectories = [
    "Sources/OpenJoystickDriverPresentation", "Sources/OpenJoystickDriver",
  ]

  /// Paths under the Controllers area that are not scanned: 20.4 follow-up after Controllers
  /// merge. Each entry is a path prefix below `Sources/OpenJoystickDriverPresentation/`.
  private static let controllersAreaFollowUp = [
    "Controllers/Inventory/",
    "MainWindow/MainWindowToolbar.swift",
    "MainWindow/MainWindowController.swift",
    "MainWindow/MainWindowController+ActivityToolbar.swift",
    "Runtime/ControllerLiveUpdates",
    "MenuBar/",
  ]

  private static func isFollowUp(_ path: String) -> Bool {
    let prefix = "Sources/OpenJoystickDriverPresentation/"
    guard path.hasPrefix(prefix) else { return false }
    let relative = String(path.dropFirst(prefix.count))
    return controllersAreaFollowUp.contains { relative.hasPrefix($0) }
  }

  private static func swiftFiles() throws -> [String] {
    try scannedDirectories.flatMap { directory -> [String] in
      let root = repository.appendingPathComponent(directory)
      let enumerator = try #require(
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      )
      return enumerator.compactMap { ($0 as? URL)?.path }
        .filter { $0.hasSuffix(".swift") }
        .map { String($0.dropFirst(repository.path.count + 1)) }
    }.sorted()
  }

  private static func findings() throws -> [UnlabeledControl] {
    try swiftFiles().filter { !isFollowUp($0) }.flatMap { path -> [UnlabeledControl] in
      let source = try String(
        contentsOf: repository.appendingPathComponent(path),
        encoding: .utf8
      )
      return AccessibilityAudit.audit(source: source, path: path)
    }
  }

  @Test
  func everyControlHasAnAccessibleName() throws {
    let unlabeled = try Self.findings()
    #expect(
      unlabeled.isEmpty,
      "Unlabeled controls:\n\(unlabeled.map(\.description).joined(separator: "\n"))"
    )
  }

  @Test
  func theAuditCoversTheAppSources() throws {
    #expect(try Self.swiftFiles().count > 100)
  }

  @Test
  func everyFollowUpEntryNamesExistingSources() throws {
    let files = try Self.swiftFiles().filter(Self.isFollowUp)
    for entry in Self.controllersAreaFollowUp {
      let prefix = "Sources/OpenJoystickDriverPresentation/" + entry
      #expect(files.contains { $0.hasPrefix(prefix) }, "No source matches \(entry)")
    }
  }

  @Test
  func aTitledButtonNeedsNoLabel() {
    let source = """
      struct V: View {
        var body: some View {
          Button("Save") {}
          Button(action: {}) { Text("Save") }
          Button { } label: { Label("Save", systemImage: "tray") }
          Toggle("On", isOn: $on)
          Toggle(isOn: $on) { Text("On") }
          Picker("Mode", selection: $mode) { Text("A") }
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }

  @Test
  func anIconOnlyControlIsListed() {
    let source = """
      struct V: View {
        var body: some View {
          Button(action: {}) { Image(systemName: "gear") }
          Button { } label: { OJDSystemSymbol(name: "gear", fallback: nil) }
          Slider(value: $value, in: 0...1)
          Picker(selection: $mode) { Text("A") }
          Toggle(isOn: $on) { Image(systemName: "gear") }
          Image(systemName: "gear")
          TextField("", text: $text)
        }
      }
      """
    let findings = AccessibilityAudit.audit(source: source, path: "V.swift")
    #expect(findings.map(\.line) == [3, 4, 5, 6, 7, 8, 9])
  }

  @Test
  func aSymbolNamesItselfUnlessItsFallbackIsALiteral() {
    let source = """
      struct V: View {
        var body: some View {
          OJDSystemSymbol(name: "gear", fallback: OJDLocalized.string("common.status"))
          OJDSystemSymbol(name: "gear", fallback: nil)
          OJDSystemSymbol(name: "arrow.right", fallback: "->")
          OJDSystemSymbol(name: "arrow.right", fallback: "->").accessibilityHidden(true)
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").map(\.line) == [5])
  }

  @Test
  func anAccessibilityLabelOrHiddenImageNamesTheControl() {
    let source = """
      struct V: View {
        var body: some View {
          Button(action: {}) { Image(systemName: "gear") }.ojdAccessibilityLabel("Settings")
          Slider(value: $value, in: 0...1)
            .accessibilityLabel(Text("Level"))
          Picker(selection: $mode) { Text("A") }.labelsHidden()
            .ojdAccessibilityLabel(title)
          Image(systemName: "gear").accessibilityHidden(true)
          Image(decorative: "gear")
        }
      }
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }

  @Test
  func commentsAndInterpolatedStringsDoNotHideOrInventControls() {
    let source = """
      // Button(action: {}) { Image(systemName: "gear") }
      let text = "\\(Button("x") { Image(systemName: "gear") })"
      """
    #expect(AccessibilityAudit.audit(source: source, path: "V.swift").isEmpty)
  }
}
