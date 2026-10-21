#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Library area: the controller records and mod packages that `ojd record` and `ojd mod`
  /// manage. The list column holds the records and mods; the detail column shows the selected
  /// one in full.
  struct LibraryAreaView: View {
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var model: LibraryViewModel

    let column: MainWindowColumn

    @ViewBuilder
    var body: some View {
      switch column {
      case .list: LibraryListView(model: model)
      case .detail: LibraryDetailView(runtime: runtime, model: model)
      }
    }
  }

  struct LibraryListView: View {
    @ObservedObject
    var model: LibraryViewModel

    var body: some View {
      VStack(spacing: 0) {
        Picker(OJDLocalized.string("library.records"), selection: $model.scope) {
          ForEach(LibraryScope.allCases) { scope in
            Text(OJDLocalized.string(scope.titleKey)).tag(scope)
          }
        }.pickerStyle(SegmentedPickerStyle()).labelsHidden().padding(.horizontal, 16)
          .padding(.vertical, 12)
        List(selection: selection) {
          Section(header: recordsHeader) {
            if model.visibleRecords.isEmpty && (isSearching || model.records.skipped.isEmpty) {
              emptyLine(isSearching ? "library.search.noMatches" : "library.records.empty.title")
            }
            ForEach(model.visibleRecords) { item in recordRow(item) }
            if model.scope == .installed && !isSearching {
              ForEach(model.records.skipped) { skipped in skippedRow(skipped) }
            }
          }
          if model.scope == .installed {
            Section(header: Text(OJDLocalized.string("library.mods"))) {
              if model.visibleMods.isEmpty {
                emptyLine(isSearching ? "library.search.noMatches" : "library.mods.empty.title")
              }
              ForEach(model.visibleMods) { mod in modRow(mod) }
            }
          }
        }.listStyle(InsetListStyle())
      }.onAppear { model.reload() }
    }

    private var isSearching: Bool {
      !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selection: Binding<LibrarySelection?> {
      Binding(get: { model.selection }, set: { model.select($0) })
    }

    /// The built-in records show their number beside the title.
    @ViewBuilder
    private var recordsHeader: some View {
      switch model.scope {
      case .installed: Text(OJDLocalized.string("library.records"))
      case .builtIn:
        HStack {
          Text(OJDLocalized.string("library.builtIn"))
          Spacer()
          Text(model.records.builtIn.count.formatted())
        }.ojdAccessibilityValue(model.records.builtIn.count.formatted())
      }
    }

    private func emptyLine(_ key: String) -> some View {
      Text(OJDLocalized.string(key)).foregroundColor(.secondary)
    }

    private func recordRow(_ item: LibraryRecordItem) -> some View {
      let summary = OJDLocalized.formatted(
        "library.record.detail",
        item.family,
        item.layer.libraryTitle
      )
      return VStack(alignment: .leading, spacing: 2) {
        Text(item.identity)
        Text(summary).font(.caption).foregroundColor(.secondary)
        if let patch = item.patchedBy {
          Text(OJDLocalized.formatted("library.record.patchedBy", patch)).font(.caption)
            .foregroundColor(.secondary)
        }
      }.tag(LibrarySelection.record(item.model)).ojdAccessibilityLabel(item.identity)
        .ojdAccessibilityValue(summary)
    }

    private func skippedRow(_ skipped: LibrarySkippedFile) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(skipped.path)
        Text(OJDLocalized.formatted("library.record.skipped", skipped.problem)).font(.caption)
          .foregroundColor(.secondary)
      }.ojdAccessibilityLabel(skipped.path).ojdAccessibilityValue(skipped.problem)
    }

    private func modRow(_ mod: LibraryModItem) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(mod.name)
        if let summary = mod.summary {
          Text(summary).font(.caption).foregroundColor(.secondary)
        }
      }.tag(LibrarySelection.mod(mod.name)).ojdAccessibilityLabel(mod.name)
        .ojdAccessibilityValue(mod.summary ?? "")
    }
  }

  extension LibraryModItem {
    /// The version and author in one line; nil when the package names neither.
    var summary: String? {
      switch (version, author) {
      case (let version?, let author?):
        return OJDLocalized.formatted("library.mod.detail", version, author)
      case (let single?, nil), (nil, let single?): return single
      case (nil, nil): return nil
      }
    }
  }

  extension ControllerRecordLayer {
    /// The layer's name for the person.
    var libraryTitle: String {
      switch self {
      case .driver: return OJDLocalized.string("library.layer.driver")
      case .bundled: return OJDLocalized.string("library.builtIn")
      case .package: return OJDLocalized.string("library.layer.package")
      case .global: return OJDLocalized.string("library.layer.global")
      case .user: return OJDLocalized.string("library.layer.user")
      case .profile: return OJDLocalized.string("controllers.activeProfile")
      }
    }
  }

  struct LibraryConfirmationSheet: View {
    let confirmation: LibraryConfirmation
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text(confirmation.title).font(.headline).fixedSize(horizontal: false, vertical: true)
        Text(confirmation.message).foregroundColor(Color(NSColor.secondaryLabelColor))
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel"), action: cancel).keyboardShortcut(
            .cancelAction
          ).ojdAccessibilityLabel(OJDLocalized.string("a11y.library.cancel"))
          Button(confirmation.confirmTitle, action: confirm).keyboardShortcut(.defaultAction)
            .ojdAccessibilityLabel(confirmation.confirmTitle)
        }
      }.padding(20).frame(width: 420)
    }
  }

  @MainActor
  enum LibraryFilePicker {
    static func chooseRecordOrModFolder() -> URL? {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.json, .folder]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = true
      panel.message = OJDLocalized.string("library.recordOrMod.pick")
      panel.prompt = OJDLocalized.string("library.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }

    /// The packet capture: JSON lines, which no content type names.
    static func chooseCapture() -> URL? {
      chooseFile(message: "library.test.packets.pick")
    }

    static func chooseExpectation() -> URL? {
      chooseFile(message: "library.test.expect.pick", type: .json)
    }

    private static func chooseFile(message: String, type: UTType? = nil) -> URL? {
      let panel = NSOpenPanel()
      if let type { panel.allowedContentTypes = [type] }
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.message = OJDLocalized.string(message)
      panel.prompt = OJDLocalized.string("library.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }
  }

#endif
