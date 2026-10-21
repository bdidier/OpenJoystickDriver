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
      Section(OJDLocalized.string("settings.commandLineTool")) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(Self.statusText(commandLineTool.status, linkPath: commandLineTool.link.linkURL.path))
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          switch commandLineTool.status.state {
          case .installed:
            Button(OJDLocalized.string("settings.commandLineTool.uninstall")) {
              confirmingUninstall = true
            }
          case .missing, .linkedElsewhere, .broken:
            Button(OJDLocalized.string("settings.commandLineTool.install")) {
              commandLineTool.install()
            }
          case .blockedByFile: EmptyView()
          }
        }
        if let message = commandLineTool.errorMessage {
          Text(message).foregroundColor(Color(NSColor.systemOrange))
            .fixedSize(horizontal: false, vertical: true)
        }
      }.onAppear { commandLineTool.refresh() }
        .alert(isPresented: $confirmingUninstall, content: uninstallAlert)
    }

    private func uninstallAlert() -> Alert {
      Alert(
        title: Text(OJDLocalized.string("settingsPane.commandLine.uninstallTitle")),
        message: Text(
          OJDLocalized.formatted(
            "settingsPane.commandLine.uninstallMessage",
            commandLineTool.link.linkURL.path
          )
        ),
        primaryButton: .destructive(
          Text(OJDLocalized.string("settingsPane.commandLine.uninstallConfirm"))
        ) { commandLineTool.uninstall() },
        secondaryButton: .cancel(Text(OJDLocalized.string("common.cancel")))
      )
    }

    static func statusText(_ status: CommandLineToolLinkStatus, linkPath path: String) -> String {
      switch status.state {
      case .missing: return OJDLocalized.formatted("settings.commandLineTool.notInstalled", path)
      case .installed: return OJDLocalized.formatted("settings.commandLineTool.installed", path)
      case .linkedElsewhere, .broken:
        guard let target = status.target else {
          return OJDLocalized.formatted("settings.commandLineTool.linkTargetUnreadable", path)
        }
        return OJDLocalized.formatted("settings.commandLineTool.linkedElsewhere", path, target)
      case .blockedByFile: return OJDLocalized.formatted("settings.commandLineTool.blocked", path)
      }
    }
  }

#endif
