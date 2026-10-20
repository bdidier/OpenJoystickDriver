import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// `ojd controller claim`: sets `server` to `OJD` for the controller's model, so OJD serves it.
struct ControllerClaimCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "claim",
    abstract: CLILocalized.text("cli.controller.claim.abstract"),
    discussion: CLILocalized.text("cli.controller.claim.discussion")
  )

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.dry_run"))
  )
  var dryRun = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await ControllerServerChange.run(
      .ojd,
      controller: controller,
      dryRun: dryRun,
      global: global
    )
  }
}

/// `ojd controller release`: sets `server` to `System` for the controller's model, so the system
/// serves it.
struct ControllerReleaseCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "release",
    abstract: CLILocalized.text("cli.controller.release.abstract"),
    discussion: CLILocalized.text("cli.controller.release.discussion")
  )

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.dry_run"))
  )
  var dryRun = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await ControllerServerChange.run(
      .system,
      controller: controller,
      dryRun: dryRun,
      global: global
    )
  }
}
