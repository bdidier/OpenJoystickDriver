import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Who serves a controller, in the words of `ojd controller ownership`: `native` leaves it to
/// macOS, `virtual` lets OJD seize it and publish a virtual gamepad.
enum OwnershipChoice: String, ExpressibleByArgument, CaseIterable, Encodable, Sendable {
  case native
  case virtual

  init(_ ownership: ControllerServer) {
    self = ownership == .system ? .native : .virtual
  }

  /// The record's `ownership` value for this choice.
  var ownership: ControllerServer { self == .native ? .system : .ojd }
}

struct ControllerOwnershipCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ownership",
    abstract: CLILocalized.text("cli.controller.ownership.abstract"),
    discussion: CLILocalized.text("cli.controller.ownership.discussion")
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    let controller: String
    let identity: String
    let ownership: OwnershipChoice
    let previous: OwnershipChoice
    let file: String
    let created: Bool
    let dryRun: Bool
  }

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.ownership.choice"),
      valueName: "choice"
    )
  )
  var choice: OwnershipChoice

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.dry_run"))
  )
  var dryRun = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let selector = controller
      let device = try await ServiceConnection.request { try await selector.resolve(with: $0) }
      let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      let records = RecordStore.load()
      try Self.checkSupported(
        device,
        server: records.records[model]?.server ?? .system,
        accessRoute: records.records[model]?.accessRoute ?? .system
      )
      let change = try Self.change(model, to: choice.ownership, records: records, device: device)
      if !dryRun { try Self.write(change) }
      let result = Result(
        controller: device.sessionToken.rawValue,
        identity: device.identity,
        ownership: choice,
        previous: OwnershipChoice(change.previous),
        file: change.file.path,
        created: change.created,
        dryRun: dryRun
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain([[result.identity, result.ownership.rawValue, result.file]])
      case .human:
        if dryRun {
          CLIOutput.stdout(
            CLILocalized.format(
              "cli.controller.ownership.dry_run",
              result.identity,
              result.ownership.rawValue,
              result.file
            )
          )
        } else {
          CLIOutput.success(
            CLILocalized.format(
              "cli.controller.ownership.success",
              result.identity,
              result.ownership.rawValue,
              result.file
            )
          )
        }
      }
    }
  }

  /// Refuses a controller whose model cannot change hands: a raw-USB family, which OJD always
  /// owns, or a model macOS does not serve natively. A model whose record already gives it to OJD
  /// counts as native, because OJD seized a controller macOS would serve.
  static func checkSupported(
    _ device: ApplicationServiceDeviceDescription,
    server: ControllerServer,
    accessRoute: ControllerAccessRoute
  ) throws {
    var input = ServingInput(device)
    input.server = server
    input.accessRoute = accessRoute
    if accessRoute != .system {
      throw CLIFailure(
        .ownershipToggleUnsupported,
        CLILocalized.format("cli.controller.ownership.raw_usb", device.identity)
      )
    }
    guard ServingPolicy.offersServerChoice(input) else {
      throw CLIFailure(
        .ownershipToggleUnsupported,
        CLILocalized.format("cli.controller.ownership.not_native", device.identity)
      )
    }
  }

  private static func change(
    _ model: ControllerModelID,
    to ownership: ControllerServer,
    records: ControllerRecordSet,
    device: ApplicationServiceDeviceDescription
  ) throws -> ControllerOwnershipWriter.Change {
    do {
      return try ControllerOwnershipWriter.change(
        model,
        to: ownership,
        records: records,
        directory: RecordStore.directory
      )
    } catch {
      switch error {
      case .noRecord:
        throw CLIFailure(
          .ownershipToggleUnsupported,
          CLILocalized.format(
            "cli.controller.ownership.no_record",
            device.identity,
            device.identity
          )
        )
      case .invalidFile(let problem), .invalidResult(let problem):
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format(
            "cli.controller.ownership.invalid",
            RecordStore.directory.appendingPathComponent(
              ControllerRecordSet.fileName(for: model)
            ).path,
            problem
          )
        )
      }
    }
  }

  private static func write(_ change: ControllerOwnershipWriter.Change) throws {
    do { try ControllerOwnershipWriter.write(change) } catch {
      throw CLIFailure(
        .fileAccessFailed,
        CLILocalized.format(
          "cli.record.install.failed",
          change.file.path,
          error.localizedDescription
        )
      )
    }
  }
}
