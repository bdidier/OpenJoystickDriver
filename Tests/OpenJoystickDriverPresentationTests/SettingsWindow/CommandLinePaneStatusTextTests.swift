#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import Testing

  @testable import OpenJoystickDriverPresentation

  @Suite
  struct CommandLinePaneStatusTextTests {
    @Test
    func linkWithoutReadableTargetSaysSo() {
      for state in [CommandLineToolLinkStatus.State.linkedElsewhere, .broken] {
        let text = CommandLinePaneView.statusText(
          CommandLineToolLinkStatus(state: state, path: "/usr/local/bin/ojd"),
          linkPath: "/usr/local/bin/ojd"
        )
        #expect(
          text
            == OJDLocalized.formatted(
              "settings.commandLineTool.linkTargetUnreadable",
              "/usr/local/bin/ojd"
            )
        )
      }
    }

    @Test
    func linkWithTargetNamesIt() {
      let text = CommandLinePaneView.statusText(
        CommandLineToolLinkStatus(state: .broken, path: "/l", target: "/gone"),
        linkPath: "/l"
      )
      #expect(
        text == OJDLocalized.formatted("settings.commandLineTool.linkedElsewhere", "/l", "/gone")
      )
    }
  }
#endif
