#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The Xbox USB driver extension section of Settings > Advanced: its state, and Uninstall while
  /// it is active. Problems with the driver show in the main window's problem banner.
  struct DriverExtensionSection: View {
    @ObservedObject
    var runtime: RuntimeViewModel
    @State
    private var confirmsUninstall = false

    var body: some View {
      Section(OJDLocalized.string("setup.driverTitle")) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(OJDLocalized.string(detailKey)).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          if runtime.systemExtensionSetupState == .active {
            Button(OJDLocalized.string("cli.login.uninstall_action")) { confirmsUninstall = true }
          }
        }
      }.alert(isPresented: $confirmsUninstall) {
        Alert(
          title: Text(OJDLocalized.string("cli.login.uninstall_action")),
          message: Text(OJDLocalized.string("setup.uninstallDetail")),
          primaryButton: .destructive(Text(OJDLocalized.string("cli.login.uninstall_action"))) {
            Task { @MainActor in await runtime.uninstallSystemExtension() }
          },
          secondaryButton: .cancel()
        )
      }
    }

    private var detailKey: String {
      switch runtime.systemExtensionSetupState {
      case .checking: return "setup.checkingDetail"
      case .active: return "setup.activeDetail"
      case .missingEmbedded: return "setup.missingDetail"
      case .invalid: return "setup.invalidDetail"
      case .awaitingApproval: return "setup.approvalDetail"
      case .needsActivation, .replacementNeeded, .failed: return "setup.repairDetail"
      }
    }
  }

#endif
