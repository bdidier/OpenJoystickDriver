#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  /// The Library area: the controller records and mod packages that `ojd record` and `ojd mod`
  /// manage.
  struct LibraryAreaView: View {
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var model: LibraryViewModel

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          PageHeader(
            title: OJDLocalized.string("library.title"),
            subtitle: OJDLocalized.string("library.subtitle")
          )
          feedback
          recordsSection
          modsSection
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
      }.onAppear { model.reload() }.sheet(item: $model.pending) { pending in
        LibraryConfirmationSheet(
          confirmation: pending.confirmation,
          cancel: { model.cancelPending() },
          confirm: {
            if model.confirmPending() { Task { @MainActor in await runtime.refresh() } }
          }
        )
      }
    }

    @ViewBuilder
    private var feedback: some View {
      if let failure = model.failure {
        InlineErrorView(
          message: failure.message,
          code: failure.code,
          detailsTitle: OJDLocalized.string("library.details"),
          detailsAccessibilityLabel: OJDLocalized.string("a11y.library.details"),
          actionTitle: OJDLocalized.string("library.dismiss"),
          actionAccessibilityLabel: OJDLocalized.string("a11y.library.dismissError")
        ) { model.dismissFailure() }
      }
      if let notice = model.notice {
        HStack(alignment: .firstTextBaseline) {
          OJDSystemSymbol(
            name: SemanticState.healthy.presentation.symbolName,
            fallback: OJDLocalized.string("common.status")
          ).foregroundColor(Color(SemanticState.healthy.presentation.tone.color))
            .accessibilityHidden(true)
          Text(notice).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Button(OJDLocalized.string("library.dismiss")) { model.dismissNotice() }
            .ojdAccessibilityLabel(OJDLocalized.string("a11y.library.dismissNotice"))
        }.ojdAccessibilityLabel(notice)
      }
    }

    private var recordsSection: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(OJDLocalized.string("library.records")).font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button(OJDLocalized.string("library.validate")) {
            if let url = LibraryFilePicker.chooseRecordFile() { model.validateRecord(at: url) }
          }.ojdAccessibilityLabel(OJDLocalized.string("a11y.library.validateRecord"))
          Button(OJDLocalized.string("library.installRecord")) {
            if let url = LibraryFilePicker.chooseRecordFile() {
              model.beginInstallRecord(from: url)
            }
          }.ojdAccessibilityLabel(OJDLocalized.string("a11y.library.installRecord"))
        }
        Text(OJDLocalized.plural("library.records.bundled", count: model.records.bundledCount))
          .font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        if model.records.items.isEmpty && model.records.skipped.isEmpty {
          EmptyStateView(
            symbol: "doc.badge.plus",
            title: OJDLocalized.string("library.records.empty.title"),
            message: OJDLocalized.string("library.records.empty.message")
          )
        }
        ForEach(model.records.items) { item in recordRow(item) }
        ForEach(model.records.skipped) { skipped in
          VStack(alignment: .leading, spacing: 2) {
            Text(skipped.path).font(.body.weight(.medium))
            Text(OJDLocalized.formatted("library.record.skipped", skipped.problem)).font(.caption)
              .foregroundColor(Color(NSColor.secondaryLabelColor))
          }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            .ojdAccessibilityLabel(skipped.path).ojdAccessibilityValue(skipped.problem)
        }
      }
    }

    private func recordRow(_ item: LibraryRecordItem) -> some View {
      let layer = OJDLocalized.string(
        item.layer == .package ? "library.layer.package" : "library.layer.user"
      )
      return GroupBox {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(item.identity).font(.body.weight(.medium))
            Text(OJDLocalized.formatted("library.record.detail", item.family, layer)).font(.caption)
              .foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            if let file = item.file {
              Text(file.path).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
                .textSelection(.enabled)
            }
          }
          Spacer()
          if item.isRemovable {
            Button(OJDLocalized.string("library.remove")) { model.requestRemove(item) }
              .ojdAccessibilityLabel(
                OJDLocalized.formatted("a11y.library.removeRecord", item.identity)
              )
          }
        }.padding(4)
      }.ojdAccessibilityLabel(item.identity).ojdAccessibilityValue("\(item.family), \(layer)")
    }

    private var modsSection: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(OJDLocalized.string("library.mods")).font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button(OJDLocalized.string("library.validate")) {
            if let url = LibraryFilePicker.chooseModFolder() { model.validateMod(at: url) }
          }.ojdAccessibilityLabel(OJDLocalized.string("a11y.library.validateMod"))
          Button(OJDLocalized.string("library.installMod")) {
            if let url = LibraryFilePicker.chooseModFolder() { model.beginInstallMod(from: url) }
          }.ojdAccessibilityLabel(OJDLocalized.string("a11y.library.installMod"))
        }
        if model.mods.isEmpty {
          EmptyStateView(
            symbol: "shippingbox",
            title: OJDLocalized.string("library.mods.empty.title"),
            message: OJDLocalized.string("library.mods.empty.message")
          )
        }
        ForEach(model.mods) { mod in modRow(mod) }
      }
    }

    private func modRow(_ mod: LibraryModItem) -> some View {
      let summary: String
      switch (mod.version, mod.author) {
      case (let version?, let author?):
        summary = OJDLocalized.formatted("library.mod.detail", version, author)
      case (let single?, nil), (nil, let single?): summary = single
      case (nil, nil): summary = ""
      }
      return GroupBox {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(mod.name).font(.body.weight(.medium))
            if !summary.isEmpty {
              Text(summary).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            ForEach(mod.files, id: \.self) { file in
              Text(file).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            if let problem = mod.problem {
              Text(OJDLocalized.formatted("library.mod.unused", problem)).font(.caption)
                .foregroundColor(Color(SemanticTone.caution.color))
            }
          }.textSelection(.enabled)
          Spacer()
          Button(OJDLocalized.string("library.remove")) { model.requestRemove(mod) }
            .ojdAccessibilityLabel(OJDLocalized.formatted("a11y.library.removeMod", mod.name))
        }.padding(4)
      }.ojdAccessibilityLabel(mod.name).ojdAccessibilityValue(summary)
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
    static func chooseRecordFile() -> URL? {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.json]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.message = OJDLocalized.string("library.record.pick")
      panel.prompt = OJDLocalized.string("library.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }

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

    static func chooseModFolder() -> URL? {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.message = OJDLocalized.string("library.mod.pick")
      panel.prompt = OJDLocalized.string("library.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }
  }

#endif
