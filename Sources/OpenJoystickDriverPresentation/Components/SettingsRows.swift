#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct PageHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
      self.title = title
      self.subtitle = subtitle
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.largeTitle.weight(.semibold))
        if let subtitle {
          Text(subtitle).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
      }
    }
  }

#endif
