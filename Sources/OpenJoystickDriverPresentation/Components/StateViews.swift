#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The empty detail of a column: centered secondary text, as Mail shows for "No Message
  /// Selected". `ContentUnavailableView` on macOS 14 and later, the same layout built from text
  /// on macOS 12 and 13.
  struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String?

    init(symbol: String, title: String, message: String? = nil) {
      self.symbol = symbol
      self.title = title
      self.message = message
    }

    @ViewBuilder
    var body: some View {
      if #available(macOS 14, *) {
        ContentUnavailableView {
          Label(title, systemImage: symbol)
        } description: {
          if let message { Text(message) }
        }
      } else {
        VStack(spacing: 4) {
          OJDSystemSymbol(name: symbol, fallback: OJDLocalized.string("term.status")).font(
            .largeTitle
          ).foregroundColor(Color(NSColor.tertiaryLabelColor)).accessibilityHidden(true)
          Text(title).font(.headline).foregroundColor(Color(NSColor.secondaryLabelColor))
          if let message {
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor))
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  struct LoadingStateView: View {
    let message: String

    var body: some View {
      HStack(spacing: 8) {
        ProgressView()
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }
  }

  struct ServiceFailureStateView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
      GroupBox {
        HStack(alignment: .top, spacing: 10) {
          OJDSystemSymbol(
            name: SemanticState.failure.presentation.symbolName,
            fallback: OJDLocalized.string("status.needsAttention")
          ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
            Button(OJDLocalized.string("action.tryAgain"), action: retry)
          }
          Spacer(minLength: 0)
        }.padding(4)
      }.ojdAccessibilityLabel(title).ojdAccessibilityValue(message)
    }
  }

#endif
