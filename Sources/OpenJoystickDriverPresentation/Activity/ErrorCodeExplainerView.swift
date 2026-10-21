#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
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
        Text(OJDLocalized.string("console.explain.title")).font(.headline)
        TextField(OJDLocalized.string("console.explain.prompt"), text: $model.typedCode) {
          model.explain()
        }
        answer.frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.done")) { model.isPresented = false }
            .keyboardShortcut(.cancelAction)
          Button(OJDLocalized.string("console.explain.action")) { model.explain() }
            .keyboardShortcut(.defaultAction)
            .disabled(model.typedCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }.padding(20).frame(width: 420)
    }

    @ViewBuilder
    private var answer: some View {
      switch model.answer {
      case .explained(let code, let explanation)?:
        VStack(alignment: .leading, spacing: 4) {
          Text(code).font(.system(.body, design: .monospaced))
          Text(explanation).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
      case .unknown(let typed)?:
        Text(OJDLocalized.formatted("cli.explain.unknown", typed)).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
      case nil: EmptyView()
      }
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
