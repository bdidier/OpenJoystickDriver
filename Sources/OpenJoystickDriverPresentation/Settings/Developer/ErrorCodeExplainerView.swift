#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import SwiftUI

  @MainActor
  final class ErrorCodeExplainerModel: ObservableObject {
    @Published
    var typedCode = ""
    @Published
    private(set) var answer: ErrorCodeExplanation?

    func explain() { answer = ErrorCodeExplanation.lookup(typedCode) }
  }

  /// The Activity area's Explain Error Code section: the text `ojd explain` prints for a code.
  struct ErrorCodeExplainerView: View {
    @ObservedObject
    private var model: ErrorCodeExplainerModel

    init(model: ErrorCodeExplainerModel) { self.model = model }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(OJDLocalized.string("console.explain.title")).font(.headline)
        HStack {
          TextField(OJDLocalized.string("console.explain.prompt"), text: $model.typedCode) {
            model.explain()
          }.frame(maxWidth: 240)
          Button(OJDLocalized.string("console.explain.action")) { model.explain() }
            .disabled(model.typedCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        switch model.answer {
        case .explained(let code, let explanation)?:
          VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(.body, design: .monospaced))
            Text(explanation).textSelection(.enabled)
          }
        case .unknown(let typed)?:
          Text(OJDLocalized.formatted("cli.explain.unknown", typed)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        case nil: EmptyView()
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

#endif
