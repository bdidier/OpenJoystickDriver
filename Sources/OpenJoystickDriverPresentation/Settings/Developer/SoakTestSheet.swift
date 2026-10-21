#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Soak Test section of the developer tools: what the test does and the button that opens
  /// its sheet, which runs `ojd diagnose --soak`.
  struct DeveloperSoakTestSection: View {
    @ObservedObject
    var model: SoakTestModel
    @State
    private var showsSheet = false

    var body: some View {
      Section(OJDLocalized.string("developer.soakTest")) {
        Text(OJDLocalized.string("developer.soakTestDescription")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        Button(OJDLocalized.string("developer.soakTestOpen")) { showsSheet = true }
          .sheet(isPresented: $showsSheet) { SoakTestSheet(model: model) }
      }
    }
  }

  /// Asks for the soak test's duration, sample interval and memory limits, runs the test and shows
  /// its result as pass, warning, failure or skip.
  struct SoakTestSheet: View {
    @ObservedObject
    var model: SoakTestModel
    @Environment(\.presentationMode)
    private var presentationMode

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("developer.soakTest")).font(.headline)
        content
        HStack {
          Spacer()
          buttons
        }
      }.padding(20).frame(width: 440)
    }

    /// Closes the sheet after a result; Done and Escape both end here.
    private func dismissFinishedResult() {
      guard case .finished = model.state else { return }
      model.reset()
      presentationMode.wrappedValue.dismiss()
    }

    @ViewBuilder
    private var content: some View {
      switch model.state {
      case .idle:
        Form {
          TextField(
            OJDLocalized.string(SoakTestField.seconds.labelKey),
            text: $model.form.seconds
          )
          TextField(
            OJDLocalized.string(SoakTestField.interval.labelKey),
            text: $model.form.interval
          )
          TextField(
            OJDLocalized.string(SoakTestField.residentLimit.labelKey),
            text: $model.form.residentLimit
          )
          TextField(
            OJDLocalized.string(SoakTestField.footprintLimit.labelKey),
            text: $model.form.footprintLimit
          )
          Text(OJDLocalized.string("developer.soakLimitHint")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          if let problem = model.problem {
            Text(problem.message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }
        }
      case .running:
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(OJDLocalized.string("developer.soakRunning"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
      case .finished(let row):
        VStack(alignment: .leading, spacing: 6) {
          Label {
            Text(OJDLocalized.string(row.statusKey)).font(.headline)
          } icon: {
            Image(systemName: row.symbolName).foregroundColor(
              ActivityDiagnosticsView.color(of: row.status)
            )
          }
          Text(row.detail).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    @ViewBuilder
    private var buttons: some View {
      switch model.state {
      case .idle:
        Button(OJDLocalized.string("common.cancel")) { presentationMode.wrappedValue.dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(OJDLocalized.string("developer.soakStart")) { model.start() }
          .keyboardShortcut(.defaultAction).disabled(model.problem != nil)
      case .running:
        Button(OJDLocalized.string("common.stop")) { model.cancel() }
          .keyboardShortcut(.cancelAction)
      case .finished:
        Button(OJDLocalized.string("developer.soakStart")) {
          model.reset()
          model.start()
        }
        Button(OJDLocalized.string("common.done")) { dismissFinishedResult() }
          .keyboardShortcut(.defaultAction)
        // Escape works without a focused control; the button is for the shortcut only.
        Button("") { dismissFinishedResult() }.keyboardShortcut(.cancelAction).frame(
          width: 0,
          height: 0
        ).opacity(0).accessibilityHidden(true)
      }
    }
  }

#endif
