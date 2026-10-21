#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct AccessRequirementCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: SemanticTone
    let action: (() -> Void)?

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        OJDSystemSymbol(name: symbol, fallback: nil).foregroundColor(Color(tone.color)).frame(
          width: 20,
          height: 20
        ).accessibilityHidden(true)
        Text(title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        Text(value).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        if let action {
          Button(OJDLocalized.string("common.request"), action: action)
            .frame(minHeight: 28).ojdAccessibilityLabel(
              OJDLocalized.formatted("settings.requestAccess", title)
            ).ojdAccessibilityValue(value)
        }
        Spacer(minLength: 0)
      }.padding(8).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading).background(
        Color(NSColor.controlBackgroundColor)
      ).cornerRadius(8).contentShape(Rectangle()).ojdAccessibilityLabel(title)
        .ojdAccessibilityValue(value)
    }
  }

#endif
