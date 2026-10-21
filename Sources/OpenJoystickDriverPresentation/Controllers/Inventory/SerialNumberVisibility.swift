import Foundation
import OpenJoystickDriverKit

/// Whether the Controllers detail shows the selected controller's serial number. It starts hidden,
/// is not stored, and a new detail view for another controller starts hidden again.
struct SerialNumberVisibility: Equatable {
  private(set) var isRevealed = false

  mutating func toggle() { isRevealed.toggle() }

  func presentation(of serial: OJDValue) -> Presentation {
    Presentation(value: serial, isRevealed: isRevealed)
  }

  struct Presentation: Equatable {
    let value: OJDValue
    let isRevealed: Bool

    /// A missing serial number has nothing to hide, so it shows the hyphen and no eye button.
    var canToggle: Bool { value != .none }

    var isObscured: Bool { canToggle && !isRevealed }

    /// The text of the row. An obscured serial number is replaced by a placeholder of the same
    /// shape, so the real value is never in the view tree.
    var displayText: String {
      isObscured ? String(repeating: "\u{2022}", count: 12) : value.displayText
    }

    /// What VoiceOver and sentence templates read.
    var spokenText: String {
      isObscured ? OJDLocalized.string("controllers.serial.hidden") : value.spokenText
    }

    var toggleSymbolName: String { isRevealed ? "eye.slash" : "eye" }

    var toggleLabelKey: String {
      isRevealed ? "controllers.serial.hide" : "controllers.serial.show"
    }
  }
}

#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The Serial number row of the Controllers detail: blurred until the eye button reveals it.
  struct SerialNumberRow: View {
    let label: String
    let serial: OJDValue
    @Binding
    var visibility: SerialNumberVisibility

    var body: some View {
      let presentation = visibility.presentation(of: serial)
      OJDLabeledRow(label) {
        HStack(spacing: 6) {
          if presentation.isObscured {
            Text(presentation.displayText).foregroundColor(Color(NSColor.secondaryLabelColor))
              .blur(radius: 4).accessibilityHidden(true)
          } else {
            OJDValueText(value: serial).foregroundColor(Color(NSColor.secondaryLabelColor))
              .textSelection(.enabled)
          }
          if presentation.canToggle {
            Button {
              visibility.toggle()
            } label: {
              Image(systemName: presentation.toggleSymbolName)
            }.buttonStyle(.borderless).help(OJDLocalized.string(presentation.toggleLabelKey))
              .ojdAccessibilityLabel(OJDLocalized.string(presentation.toggleLabelKey))
          }
        }
      }.accessibilityElement(children: .contain).ojdAccessibilityValue(presentation.spokenText)
    }
  }

#endif
