import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// `ojd config set`: sets one tuning key in the user's record of a controller model, or in
/// `all.patch.json` without `--controller`.
struct ConfigSetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.config.set.abstract"),
    discussion: CLILocalized.text("cli.config.set.discussion")
  )

  @Argument(help: ArgumentHelp(CLILocalized.text("cli.config.group.key"), valueName: "KEY"))
  var key: String

  @Argument(help: ArgumentHelp(CLILocalized.text("cli.config.set.value"), valueName: "VALUE"))
  var value: String

  @Option(
    name: .customLong("controller"),
    help: ArgumentHelp(CLILocalized.text("cli.config.group.controller"), valueName: "VVVV:PPPP")
  )
  var controller: ControllerModelID?

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func validate() throws { _ = try ConfigChange.edit(key: key, value: value) }

  func run() async throws {
    try await ConfigChange.run(
      try ConfigChange.edit(key: key, value: value),
      controller: controller,
      global: global
    )
  }
}

/// `ojd config unset`: removes one tuning key from the user's record of a controller model, or
/// from `all.patch.json` without `--controller`.
struct ConfigUnsetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "unset",
    abstract: CLILocalized.text("cli.config.unset.abstract")
  )

  @Argument(help: ArgumentHelp(CLILocalized.text("cli.config.group.key"), valueName: "KEY"))
  var key: String

  @Option(
    name: .customLong("controller"),
    help: ArgumentHelp(CLILocalized.text("cli.config.group.controller"), valueName: "VVVV:PPPP")
  )
  var controller: ControllerModelID?

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func validate() throws { _ = try ConfigChange.edit(key: key, value: nil) }

  func run() async throws {
    try await ConfigChange.run(
      try ConfigChange.edit(key: key, value: nil),
      controller: controller,
      global: global
    )
  }
}
