#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import SwiftUI

  extension JSONSyntaxKind {
    /// System semantic colors: they follow light and dark appearance and the increased contrast
    /// setting. Keys and strings, the two kinds that fill most lines, get the blue and green
    /// that stay readable on both appearances; punctuation recedes.
    var color: NSColor {
      switch self {
      case .key: return .systemBlue
      case .string: return .systemGreen
      case .number: return .systemOrange
      case .literal: return .systemPurple
      case .punctuation: return .secondaryLabelColor
      case .space: return .labelColor
      }
    }
  }

  extension LibraryRecordText {
    /// The record JSON, colored by token, without the line break that ends the document.
    var highlighted: AttributedString {
      var shown = tokens
      if let last = shown.last, last.kind == .space, last.text.hasSuffix("\n") {
        shown.removeLast()
        let kept = String(last.text.dropLast())
        if !kept.isEmpty {
          shown.append(JSONSyntaxToken(kind: .space, text: kept, depth: last.depth))
        }
      }
      var result = AttributedString()
      for token in shown {
        var run = AttributedString(token.text)
        run.foregroundColor = Color(token.kind.color)
        result.append(run)
      }
      return result
    }
  }

  /// The record JSON in the Library detail: the code is one selectable block, and each
  /// identifier reading sits after its line as a separate element that selection and copying
  /// leave out.
  struct LibraryRecordTextView: View {
    let text: LibraryRecordText

    private static let font = Font.system(.body, design: .monospaced)

    /// The width of one character of the monospaced body font.
    private static var advance: CGFloat {
      NSFont.monospacedSystemFont(
        ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
        weight: .regular
      ).maximumAdvancement.width
    }

    /// Columns between the end of a line and its reading.
    private static let gap = 3

    var body: some View {
      ScrollView(.horizontal) {
        Text(text.highlighted).font(Self.font).textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .overlay(readings, alignment: .topLeading)
      }.contextMenu {
        Button(OJDLocalized.string("common.copyAll")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text.copyText, forType: .string)
        }
      }
    }

    /// One row per line, each as tall as a line of the block; only identifier lines have text.
    private var readings: some View {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(text.lines.enumerated()), id: \.offset) { index, line in
          if let reading = text.identifierReadings[index] {
            Text(reading).font(Self.font).foregroundColor(.secondary)
              .padding(.leading, CGFloat(line.count + Self.gap) * Self.advance)
              .ojdAccessibilityLabel(
                OJDLocalized.formatted("a11y.library.recordHexadecimal", reading)
              )
          } else {
            Text(" ").font(Self.font).accessibilityHidden(true)
          }
        }
      }.allowsHitTesting(false)
    }
  }

#endif
