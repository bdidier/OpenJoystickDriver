#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The `ojd` link section of Settings > Advanced: install or uninstall, where uninstalling asks
  /// first in a window-modal sheet.
  struct CommandLineToolSection: View {
    @ObservedObject
    var commandLineTool: CommandLineToolModel
    @State
    private var confirmingUninstall = false

    var body: some View {
      Section(OJDLocalized.string("ui.settings.commandLine.tool")) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(Self.statusText(commandLineTool.status, linkPath: commandLineTool.link.linkURL.path))
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          switch commandLineTool.status.state {
          case .installed:
            Button(OJDLocalized.string("ui.settings.commandLine.toolUninstall")) {
              confirmingUninstall = true
            }
          case .missing, .linkedElsewhere, .broken:
            Button(OJDLocalized.string("ui.settings.commandLine.toolInstall")) {
              commandLineTool.install()
            }
          case .blockedByFile: EmptyView()
          }
        }
        if let message = commandLineTool.errorMessage {
          Text(message).foregroundColor(Color(NSColor.systemOrange))
            .fixedSize(horizontal: false, vertical: true)
        }
      }.alert(isPresented: $confirmingUninstall, content: uninstallAlert)
    }

    private func uninstallAlert() -> Alert {
      Alert(
        title: Text(OJDLocalized.string("ui.settings.commandLine.uninstallTitle")),
        message: Text(
          OJDLocalized.formatted(
            "platform.macos.ui.settings.commandLine.uninstallMessage",
            commandLineTool.link.linkURL.path
          )
        ),
        primaryButton: .destructive(
          Text(OJDLocalized.string("ui.settings.commandLine.uninstallConfirm"))
        ) { commandLineTool.uninstall() },
        secondaryButton: .cancel(Text(OJDLocalized.string("action.cancel")))
      )
    }

    static func statusText(_ status: CommandLineToolLinkStatus, linkPath path: String) -> String {
      switch status.state {
      case .missing:
        return OJDLocalized.formatted(
          "platform.macos.ui.settings.commandLine.toolNotInstalled",
          path
        )
      case .installed:
        return OJDLocalized.formatted("platform.macos.ui.settings.commandLine.toolInstalled", path)
      case .linkedElsewhere, .broken:
        guard let target = status.target else {
          return OJDLocalized.formatted("ui.settings.commandLine.toolLinkTargetUnreadable", path)
        }
        return OJDLocalized.formatted("ui.settings.commandLine.toolLinkedElsewhere", path, target)
      case .blockedByFile:
        return OJDLocalized.formatted("ui.settings.commandLine.toolBlocked", path)
      }
    }
  }

#endif
