import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The SDL mapping of one persona in a `--json` result.
struct VirtualSDLReport: Encodable, Equatable {
  let guid: String
  let mapping: String
  /// False when SDL does not recognize the persona with its default hints.
  let worksWithDefaultSDLHints: Bool

  init(_ mapping: VirtualGamepadMapping) {
    guid = mapping.guid
    worksWithDefaultSDLHints = mapping.worksWithDefaultSDLHints
    self.mapping = mapping.sdlMapping
  }
}

/// The W3C Gamepad description of one persona in a `--json` result: for each index of the standard
/// layout, the control and the input of the virtual gamepad that supplies it.
struct VirtualW3CReport: Encodable, Equatable {
  struct Entry: Encodable, Equatable {
    let index: Int
    let control: String
    let source: String

    init(_ entry: VirtualGamepadMapping.W3CEntry) {
      index = entry.index
      control = entry.control.rawValue
      source = entry.source
    }
  }

  let id: String
  let buttons: [Entry]
  let axes: [Entry]

  init(_ mapping: VirtualGamepadMapping) {
    id = mapping.w3cID
    buttons = mapping.w3cButtons.map(Entry.init)
    axes = mapping.w3cAxes.map(Entry.init)
  }
}

/// The formats `ojd virtual export-mapping` writes.
enum VirtualMappingFormat: String, CaseIterable, ExpressibleByArgument {
  case sdl = "SDL"
  case w3c = "W3C"

  /// A format on the command line is its lowercase name: `sdl` or `w3c`.
  init?(argument: String) {
    guard let format = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = format
  }

  static var allValueStrings: [String] { allCases.map { CommandLineName.kebab($0.rawValue) } }
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
  CLILocalized.format("cli.virtual.sdl_hints_note", CommandLineName.kebab(profile))
}

struct VirtualExportMappingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export-mapping",
    abstract: CLILocalized.text("cli.virtual.export_mapping.abstract"),
    discussion: CLILocalized.text("cli.virtual.export_mapping.discussion")
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.export_mapping.profile"),
      valueName: "profile"
    )
  )
  var profile: VirtualHIDProfileID?

  @Option(
    help: ArgumentHelp(CLILocalized.text("cli.virtual.export_mapping.format"), valueName: "format")
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
      case .human: try Self.printHuman(report)
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
  private static func printHuman(_ report: VirtualMappingExport) throws {
    if report.format == VirtualMappingFormat.sdl.rawValue {
      for entry in report.mappings {
        guard let sdl = entry.sdl else { continue }
        // A comment line keeps the output a valid SDL mapping file.
        if !sdl.worksWithDefaultSDLHints { CLIOutput.stdout("# \(sdlHintsNote(entry.profile))") }
        CLIOutput.stdout(sdl.mapping)
      }
      return
    }
    struct Description: Encodable {
      let profile: String
      let id: String
      let buttons: [VirtualW3CReport.Entry]
      let axes: [VirtualW3CReport.Entry]
    }
    let descriptions = report.mappings.compactMap { entry in
      entry.w3c.map {
        Description(profile: entry.profile, id: $0.id, buttons: $0.buttons, axes: $0.axes)
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    CLIOutput.stdout(String(bytes: try encoder.encode(descriptions), encoding: .utf8) ?? "")
  }
}
