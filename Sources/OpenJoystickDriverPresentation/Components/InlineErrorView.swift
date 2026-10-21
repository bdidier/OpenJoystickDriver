#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The error pattern of the main window: a symbol, the message, and a Details control that
  /// shows the `ojd explain` text of the error code.
  struct InlineErrorView: View {
    let message: String
    let code: ErrorCode?
    let detailsTitle: String
    let detailsAccessibilityLabel: String
    let actionTitle: String
    let actionAccessibilityLabel: String
    let action: () -> Void
    @State
    private var showsDetails = false

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            OJDSystemSymbol(
              name: SemanticState.failure.presentation.symbolName,
              fallback: OJDLocalized.string("common.needsAttention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
              .accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if code != nil {
              Button(detailsTitle) { showsDetails.toggle() }
                .ojdAccessibilityLabel(detailsAccessibilityLabel)
            }
            Button(actionTitle, action: action).ojdAccessibilityLabel(actionAccessibilityLabel)
          }
          if showsDetails, let code {
            VStack(alignment: .leading, spacing: 4) {
              Text(code.rawValue).font(.caption.weight(.semibold))
              Text(code.localizedExplanation).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              ).fixedSize(horizontal: false, vertical: true)
            }.textSelection(.enabled)
          }
        }.padding(4)
      }.ojdAccessibilityLabel(message)
    }
  }

#endif
