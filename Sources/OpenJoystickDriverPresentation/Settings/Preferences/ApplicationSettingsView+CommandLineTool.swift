#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension ApplicationSettingsView {
    var commandLineToolSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 12) {
            Text(commandLineToolStatus).font(.caption).foregroundColor(
              Color(NSColor.secondaryLabelColor)
            ).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            switch commandLineTool.status.state {
            case .installed:
              Button(
                OJDLocalized.string("settings.commandLineTool.uninstall")
              ) { commandLineTool.uninstall() }
            case .missing, .linkedElsewhere, .broken:
              Button(
                OJDLocalized.string(
                  "settings.commandLineTool.install"
                )
              ) { commandLineTool.install() }
            case .blockedByFile: EmptyView()
            }
          }
          if let message = commandLineTool.errorMessage {
            Text(message).font(.caption).foregroundColor(Color(NSColor.systemOrange)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }
        }.padding(4).frame(maxWidth: .infinity, alignment: .topLeading)
      } label: {
        Text(OJDLocalized.string("settings.commandLineTool")).font(
          .headline
        )
      }.onAppear { commandLineTool.refresh() }
    }

    private var commandLineToolStatus: String {
      let path = commandLineTool.link.linkURL.path
      let status = commandLineTool.status
      switch status.state {
      case .missing:
        return OJDLocalized.formatted(
          "settings.commandLineTool.notInstalled",
          path
        )
      case .installed:
        return OJDLocalized.formatted(
          "settings.commandLineTool.installed",
          path
        )
      case .linkedElsewhere, .broken:
        return OJDLocalized.formatted(
          "settings.commandLineTool.linkedElsewhere",
          path,
          status.target ?? ""
        )
      case .blockedByFile:
        return OJDLocalized.formatted(
          "settings.commandLineTool.blocked",
          path
        )
      }
    }
  }

#endif
