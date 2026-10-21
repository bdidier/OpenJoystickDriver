#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Installs or uninstalls the `ojd` link; uninstalling asks first in a window-modal sheet.
  struct CommandLinePaneView: View {
    @ObservedObject
    var commandLineTool: CommandLineToolModel
    @State
    private var confirmingUninstall = false

    var body: some View {
      SettingsPaneColumn {
        GroupBox {
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
              Text(
                Self.statusText(commandLineTool.status, linkPath: commandLineTool.link.linkURL.path)
              ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
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
              Text(message).font(.caption).foregroundColor(Color(NSColor.systemOrange))
                .fixedSize(horizontal: false, vertical: true)
            }
          }.padding(4).frame(maxWidth: .infinity, alignment: .topLeading)
        } label: {
          Text(OJDLocalized.string("settings.commandLineTool")).font(.headline)
        }
      }.onAppear { commandLineTool.refresh() }.alert(isPresented: $confirmingUninstall) {
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
