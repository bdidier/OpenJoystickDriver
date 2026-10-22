import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct AccessWebCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "web",
    abstract: CLILocalized.text(
      "cli.access.web.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.web.discussion"
    ),
    subcommands: [AccessWebEnableCommand.self, AccessWebDisableCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

struct AccessWebEnableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.web.enableAbstract"),
    discussion: CLILocalized.text(
      "cli.access.web.enableDiscussion"
    )
  )

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text("cli.access.web.port"),
      valueName: "port"
    )
  )
  var port: Int?

  @Flag(
    name: .long,
    help: ArgumentHelp(CLILocalized.text("cli.access.web.automatic"))
  )
  var automatic = false

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func validate() throws {
    if automatic, port != nil {
      throw ValidationError(CLILocalized.text("cli.access.web.automaticConflict"))
    }
    if let port, !AccessWebPorts.allowed.contains(port) {
      throw ValidationError(
        CLILocalized.text("cli.access.web.portRange")
      )
    }
  }

  func run() async throws {
    try await global.run {
      try CLITerminal.confirm(
        CLILocalized.text(
          "cli.access.web.enableConfirm"
        ),
        force: force,
        needsForce: AccessText.needsForce
      )
      let port = automatic ? 0 : port
      let status = try await ServiceConnection.request {
        try await $0.setWebAccess(enabled: true, port: port)
      }
      try AccessWebCommand.print(status.web)
    }
  }
}

struct AccessWebDisableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "disable",
    abstract: CLILocalized.text(
      "cli.access.web.disableAbstract"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request {
        try await $0.setWebAccess(enabled: false, port: nil)
      }
      try AccessWebCommand.print(status.web)
    }
  }
}

extension AccessWebCommand {
  /// Prints the result of `web enable` and `web disable`.
  static func print(_ web: AccessWebStatus) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(web)
    case .plain: CLIOutput.plain([[String(web.enabled), String(web.listening), web.url ?? ""]])
    case .human:
      CLIOutput.success(
        web.enabled
          ? AccessText.web(web)
          : CLILocalized.text(
            "cli.access.web.disableSuccess"
          )
      )
    }
  }
}
