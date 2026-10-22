#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  // SF Symbol via NSImage(systemSymbolName:), else fallback text. Pass a nil fallback for a
  // decorative glyph whose meaning is already printed beside it: fallback text in a glyph-sized
  // frame wraps into a column. The symbol's accessibility label is the fallback text; a nil
  // fallback hides the symbol from VoiceOver.
  struct OJDSystemSymbol: View {
    let name: String
    let fallback: String?
    let fallbackSymbolName: String?

    init(name: String, fallback: String?, fallbackSymbolName: String? = nil) {
      self.name = name
      self.fallback = fallback
      self.fallbackSymbolName = fallbackSymbolName
    }

    var body: some View {
      let preferredImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)
      let fallbackImage = fallbackSymbolName.flatMap {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil)
      }
      switch SystemSymbolPolicy.resolution(
        preferred: name,
        fallback: fallbackSymbolName,
        preferredIsAvailable: preferredImage != nil,
        fallbackIsAvailable: fallbackImage != nil
      ) {
      case .symbol(let resolvedName):
        if resolvedName == name, let preferredImage {
          Image(nsImage: preferredImage).ojdSymbolAccessibility(fallback)
        } else if let fallbackImage {
          Image(nsImage: fallbackImage).ojdSymbolAccessibility(fallback)
        }
      case .text: if let fallback { Text(fallback).font(.caption) }
      }
    }
  }

  struct OJDListGlyphSlot<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
      content.font(.system(size: 15, weight: .medium)).frame(
        width: 28,
        height: 28,
        alignment: .center
      ).accessibilityHidden(true)
    }
  }

  struct OJDCompactSymbolButton: View {
    let symbolName: String
    let fallbackSymbolName: String?
    let label: String
    let action: () -> Void

    init(
      symbolName: String,
      fallbackSymbolName: String? = nil,
      label: String,
      action: @escaping () -> Void
    ) {
      self.symbolName = symbolName
      self.fallbackSymbolName = fallbackSymbolName
      self.label = label
      self.action = action
    }

    var body: some View {
      Button(action: action) {
        OJDSystemSymbol(name: symbolName, fallback: label, fallbackSymbolName: fallbackSymbolName)
          .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
      }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(label).help(label)
    }
  }

  extension View {
    func ojdAccessibilityLabel(_ label: String) -> some View { accessibilityLabel(Text(label)) }

    @ViewBuilder
    func ojdSymbolAccessibility(_ label: String?) -> some View {
      if let label { accessibilityLabel(Text(label)) } else { accessibilityHidden(true) }
    }

    func ojdAccessibilityValue(_ value: String) -> some View { accessibilityValue(Text(value)) }

    @ViewBuilder
    func ojdAccessibilitySelection(_ selected: Bool) -> some View {
      let value = OJDLocalized.string(
        selected ? "status.selected" : "status.notSelected"
      )
      accessibilityValue(Text(value)).accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

#endif
