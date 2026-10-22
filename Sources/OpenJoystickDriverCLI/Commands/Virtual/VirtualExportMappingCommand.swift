import ArgumentParser
import Foundation
import OpenJoystickDriverKit

extension VirtualMappingFormat: ExpressibleByArgument {
  /// A format on the command line is its lowercase name: `sdl` or `w3c`.
  public init?(argument: String) {
    guard let format = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = format
  }

  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

/// The `ojd virtual export-mapping --json` result: one entry per persona, carrying only the
/// requested format.
struct VirtualMappingExport: Encodable, Equatable {
  struct Entry: Encodable, Equatable {
    let profile: String
    let sdl: VirtualSDLReport?
    let w3c: VirtualW3CReport?
  }

  let format: String
  let mappings: [Entry]
}

/// The note for a persona that SDL does not recognize with its default hints; it names the
/// persona as the command line does.
func sdlHintsNote(_ profile: String) -> String {
  CLILocalized.format("cli.virtual.group.sdlHintsNote", CommandLineName.kebab(profile))
}

struct VirtualExportMappingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export-mapping",
    abstract: CLILocalized.text("cli.virtual.exportMapping.abstract"),
    discussion: CLILocalized.text("cli.virtual.exportMapping.discussion")
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.exportMapping.profile"),
      valueName: "profile"
    )
  )
  var profile: VirtualHIDProfileID?

  @Option(
    help: ArgumentHelp(CLILocalized.text("cli.virtual.exportMapping.format"), valueName: "format")
  )
  var format: VirtualMappingFormat = .sdl

  func run() async throws {
    try await global.run {
      let personas = profile.map { [$0] } ?? VirtualHIDProfileID.allCases
      let mappings = try personas.map { ($0, try $0.gamepadMapping()) }
      let report = VirtualMappingExport(
        format: format.rawValue,
        mappings: mappings.map { persona, mapping in
          VirtualMappingExport.Entry(
            profile: persona.rawValue,
            sdl: format == .sdl ? VirtualSDLReport(mapping) : nil,
            w3c: format == .w3c ? VirtualW3CReport(mapping) : nil
          )
        }
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain: CLIOutput.plain(Self.plainRows(report))
      case .human: try Self.printHuman(format, personas)
      }
    }
  }

  private static func plainRows(_ report: VirtualMappingExport) -> [[String]] {
    report.mappings.flatMap { entry -> [[String]] in
      if let sdl = entry.sdl {
        return [[CommandLineName.kebab(entry.profile), sdl.guid, sdl.mapping]]
      }
      guard let w3c = entry.w3c else { return [] }
      return w3c.buttons.map {
        [CommandLineName.kebab(entry.profile), "button", "\($0.index)", $0.control, $0.source]
      }
        + w3c.axes.map {
          [CommandLineName.kebab(entry.profile), "axis", "\($0.index)", $0.control, $0.source]
        }
    }
  }

  /// SDL prints one mapping line per persona, which is a valid SDL mapping file. W3C prints one
  /// JSON array of the descriptions.
  private static func printHuman(
    _ format: VirtualMappingFormat,
    _ personas: [VirtualHIDProfileID]
  )
    throws
  {
    CLIOutput.stdout(
      try format.document(for: personas) { sdlHintsNote($0.rawValue) }
    )
  }
}
