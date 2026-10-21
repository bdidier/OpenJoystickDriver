#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension OverviewView {

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          PageHeader(title: OJDLocalized.string(MainWindowArea.status.titleKey))
          SystemExtensionSetupCard(
            viewModel: viewModel,
            supportReport: supportReport,
            navigation: navigation
          )
          statusCard
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    private var statusCard: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            StatusBadge(status: statusTitle, semanticState: statusSemanticState)
            Spacer()
            Button(OJDLocalized.string("common.refresh")) {
              Task { @MainActor in await viewModel.refresh() }
            }
          }
          Text(statusDetail).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }.padding(4)
      }.ojdAccessibilityLabel(
        OJDLocalized.string("settings.controllerStatus")
      ).ojdAccessibilityValue(statusDetail)
    }

    private var statusTitle: String {
      switch viewModel.statusState {
      case .loading: return OJDLocalized.string("status.starting")
      case .available(let status): return status.readinessLabel
      case .unavailable, .error:
        return OJDLocalized.string("common.needsAttention")
      }
    }

    private var statusSemanticState: SemanticState {
      switch viewModel.statusState {
      case .available(let status): return status.readiness == .ready ? .healthy : .attention
      case .loading: return .loading
      case .unavailable, .error: return .failure
      }
    }

    private var statusDetail: String {
      switch viewModel.statusState {
      case .loading:
        return OJDLocalized.string(
          "status.checkingControllerAccess"
        )
      case .unavailable(let message), .error(let message): return message
      case .available(let status): return status.deviceCountLabel
      }
    }
  }

#endif
