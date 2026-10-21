#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  extension View {
    /// The grouped form look on macOS 13 and later; macOS 12 shows the plain form, which does not
    /// scroll by itself and so sits in a scroll view. Every content form of the main window goes
    /// through this.
    @ViewBuilder
    func ojdGroupedForm() -> some View {
      if #available(macOS 13, *) {
        formStyle(.grouped)
      } else {
        ScrollView { self.padding() }
      }
    }
  }

  /// A label and its content as one form row: `LabeledContent` on macOS 13 and later, a label and
  /// trailing content on macOS 12.
  struct OJDLabeledRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
      self.label = label
      self.content = content()
    }

    var body: some View {
      if #available(macOS 13, *) {
        LabeledContent(label) { content }
      } else {
        HStack(alignment: .firstTextBaseline) {
          Text(label)
          Spacer(minLength: 8)
          content.multilineTextAlignment(.trailing)
        }
      }
    }
  }

  /// A label and its value as one form row. A missing value shows the hyphen of ``OJDValue``.
  struct OJDLabeledValue: View {
    let label: String
    let value: OJDValue

    init(_ label: String, _ value: OJDValue) {
      self.label = label
      self.value = value
    }

    init(_ label: String, _ value: String?) { self.init(label, OJDValue(value)) }

    var body: some View {
      OJDLabeledRow(label) {
        OJDValueText(value: value).foregroundColor(Color(NSColor.secondaryLabelColor))
          .textSelection(.enabled)
      }
    }
  }

#endif
