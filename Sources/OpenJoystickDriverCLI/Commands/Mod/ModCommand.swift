import ArgumentParser

struct ModCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mod",
    abstract: CLILocalized.text("cli.mod.group.abstract"),
    discussion: CLILocalized.text("cli.mod.group.discussion"),
    subcommands: [
      ModValidateCommand.self, ModInstallCommand.self, ModListCommand.self, ModRemoveCommand.self,
    ]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}
