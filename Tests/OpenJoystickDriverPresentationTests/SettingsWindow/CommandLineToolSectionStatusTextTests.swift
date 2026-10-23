#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import Testing

  @testable import OpenJoystickDriverPresentation

  @Suite
  @MainActor
  struct CommandLineToolSectionStatusTextTests {
    @Test
    func linkWithoutReadableTargetSaysSo() {
      for state in [CommandLineToolLinkStatus.State.linkedElsewhere, .broken] {
        let text = CommandLineToolSection.statusText(
          CommandLineToolLinkStatus(state: state, path: "/usr/local/bin/ojd"),
          linkPath: "/usr/local/bin/ojd"
        )
        #expect(
          text
            == OJDLocalized.formatted(
              "ui.settings.commandLine.toolLinkTargetUnreadable",
              "/usr/local/bin/ojd"
            )
        )
      }
    }

    @Test
    func linkWithTargetNamesIt() {
      let text = CommandLineToolSection.statusText(
        CommandLineToolLinkStatus(state: .broken, path: "/l", target: "/gone"),
        linkPath: "/l"
      )
      #expect(
        text == OJDLocalized.formatted("ui.settings.commandLine.toolLinkedElsewhere", "/l", "/gone")
      )
    }
  }
#endif
