#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The detail column of the Library: everything `ojd record show` and `ojd mod list` print
  /// for the selected record or mod.
  struct LibraryDetailView: View {
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var model: LibraryViewModel

    var body: some View {
      Form {
        feedback
        if let detail = model.recordDetail {
          recordSections(detail)
        } else if let mod = model.selectedMod {
          modSections(mod)
        } else {
          Section { Text(OJDLocalized.string("library.detail.empty")).foregroundColor(.secondary) }
        }
      }.ojdGroupedForm().sheet(item: $model.pending) { pending in
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
      if model.failure != nil || model.notice != nil {
        Section {
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
      }
    }

    // MARK: Record

    @ViewBuilder
    private func recordSections(_ detail: LibraryRecordDetail) -> some View {
      Section {
        OJDLabeledValue(OJDLocalized.string("library.field.identity"), detail.item.identity)
        OJDLabeledValue(OJDLocalized.string("library.field.family"), detail.item.family)
        OJDLabeledValue(
          OJDLocalized.string("library.field.source"),
          detail.item.layer.libraryTitle
        )
        OJDLabeledValue(OJDLocalized.string("library.field.file"), detail.item.file?.path)
        OJDLabeledValue(OJDLocalized.string("library.field.transport"), detail.transport)
        ForEach(detail.notes, id: \.self) { note in
          Text(note).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      if let run = model.testRun, run.model == detail.item.model { testSection(run) }
      Section(header: Text(OJDLocalized.string("library.section.fields"))) {
        ForEach(detail.fields) { field in
          OJDLabeledValue(field.name, field.layer.libraryTitle)
        }
      }
      Section(header: Text(OJDLocalized.string("cli.controller.show.label.record"))) {
        OJDValueText(detail.document).font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
      }
    }

    private func testSection(_ run: LibraryTestRun) -> some View {
      Section(header: Text(OJDLocalized.string("library.section.testResult"))) {
        if run.result.matches {
          Text(
            OJDLocalized.formatted(
              "cli.record.test.matched",
              run.model.description,
              run.result.inputReports
            )
          )
        } else {
          Text(
            OJDLocalized.formatted(
              "cli.record.test.mismatch",
              run.model.description,
              run.expectation,
              run.result.differences.count
            )
          )
          ForEach(run.result.differences, id: \.field) { difference in
            Text(
              OJDLocalized.formatted(
                "cli.record.test.difference",
                difference.field,
                difference.expected,
                difference.actual
              )
            ).textSelection(.enabled)
          }
        }
      }
    }

    // MARK: Mod

    @ViewBuilder
    private func modSections(_ mod: LibraryModItem) -> some View {
      Section {
        OJDLabeledValue(OJDLocalized.string("cli.controller.show.label.name"), mod.name)
        OJDLabeledValue(OJDLocalized.string("library.field.version"), mod.version)
        OJDLabeledValue(OJDLocalized.string("library.field.author"), mod.author)
        if let problem = mod.problem {
          Text(OJDLocalized.formatted("library.mod.unused", problem))
            .foregroundColor(Color(SemanticTone.caution.color))
        }
      }
      Section(header: Text(OJDLocalized.string("library.section.files"))) {
        if mod.files.isEmpty { OJDValueText(nil) }
        ForEach(mod.files, id: \.self) { file in Text(file).textSelection(.enabled) }
      }
    }
  }

#endif
