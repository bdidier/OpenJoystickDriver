#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  @MainActor
  final class ErrorCodeExplainerModel: ObservableObject {
    /// Whether the main window shows the Explain Error Code sheet.
    @Published
    var isPresented = false
    @Published
    var typedCode = ""
    @Published
    private(set) var answer: ErrorCodeExplanation?

    func explain() { answer = ErrorCodeExplanation.lookup(typedCode) }
  }

  /// The Explain Error Code sheet: the text `ojd explain` prints for a code.
  struct ErrorCodeExplainerView: View {
    @ObservedObject
    private var model: ErrorCodeExplainerModel

    init(model: ErrorCodeExplainerModel) { self.model = model }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(OJDLocalized.string("ui.console.explain.title")).font(.headline)
        TextField(OJDLocalized.string("ui.console.explain.prompt"), text: $model.typedCode) {
          model.explain()
        }
        answer.frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.done")) { model.isPresented = false }
            .keyboardShortcut(.cancelAction)
          Button(OJDLocalized.string("ui.console.explain.action")) { model.explain() }
            .keyboardShortcut(.defaultAction)
            .disabled(model.typedCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }.padding(20).frame(width: 420)
    }

    @ViewBuilder
    private var answer: some View {
      switch model.answer {
      case .explained(let facts)?:
        VStack(alignment: .leading, spacing: 4) {
          Text(facts.code).font(.system(.body, design: .monospaced))
          ForEach(Self.factLines(facts), id: \.self) { line in
            Text(line).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
          Text(facts.explanation).textSelection(.enabled).fixedSize(
            horizontal: false,
            vertical: true
          ).padding(.top, 4)
        }
      case .unknown(let typed)?:
        Text(OJDLocalized.formatted("cli.explain.group.unknown", typed)).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
      case nil: EmptyView()
      }
    }
  }

  extension ErrorCodeExplainerView {
    /// The labeled lines that `ojd explain` prints between the code and the explanation.
    static func factLines(_ facts: ErrorCodeFacts) -> [String] {
      var lines = [OJDLocalized.formatted("cli.explain.group.area", facts.area)]
      if let exitCode = facts.exitCode {
        lines.append(OJDLocalized.formatted("cli.explain.group.exitCode", String(exitCode)))
      }
      if let wire = facts.wire {
        lines.append(OJDLocalized.formatted("cli.explain.group.wire", wire))
      }
      return lines
    }
  }

  /// Presents the Explain Error Code sheet over the window that holds it.
  struct ErrorCodeExplainerSheetHost: View {
    @ObservedObject
    var model: ErrorCodeExplainerModel

    var body: some View {
      Color.clear.sheet(isPresented: $model.isPresented) { ErrorCodeExplainerView(model: model) }
    }
  }

#endif
