#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  // MARK: - Overview and status

  struct OverviewView: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let supportReport: SupportReportModel
    @ObservedObject
    var navigation: MainWindowNavigationModel
  }

  struct StatusBadge: View {
    let status: String
    let semanticState: SemanticState

    var body: some View {
      HStack(spacing: 7) {
        OJDSystemSymbol(
          name: semanticState.presentation.symbolName,
          fallback: OJDLocalized.string("common.status")
        ).accessibilityHidden(true)
        Text(status).font(.headline.weight(.semibold))
      }.foregroundColor(Color(semanticState.presentation.tone.color)).ojdAccessibilityLabel(
        OJDLocalized.string("common.status")
      ).ojdAccessibilityValue(status)
    }
  }

#endif
