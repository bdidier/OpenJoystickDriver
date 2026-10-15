/// The CLI-to-GUI coverage matrix of `design.md` D10, held as data. It lives with the tests
/// because only the 17.5 coverage test reads it; the GUI does not consume it. Task 20.3 builds the
/// GUI places and keeps this table as the check that none is missed.
///
/// D10 states the matrix per command group, so an entry covers every command whose path starts with
/// its `prefix`. D10 lists no exemption: "CLI is a subset of GUI (every command has a GUI place)".
/// Every command therefore maps to a place, and this file has no exemption list.
struct GUIPlace: Equatable {
  /// The command path the entry covers, such as `["config", "show"]`.
  let prefix: [String]
  /// The GUI area of D10 that holds the command.
  let area: String
  /// The main menu entry of D10, or nil where D10 says none.
  let mainMenu: String?
  /// The status item entry of D10, or nil where D10 says none.
  let statusItem: String?
}

/// The GUI place of one `--json` field, for a field a command prints that the GUI shows as a named
/// element. The command-group table above says where a command lives; this one says where a field
/// of its output shows.
struct GUIField: Equatable {
  /// The command path, such as `["controller", "show"]`.
  let command: [String]
  /// The dotted `--json` field, such as `serving.route`.
  let field: String
  /// The element of the GUI area that shows the field.
  let place: String
}

enum GUICoverageMatrix {
  /// Fields the GUI shows by name. Task 24.5: the serving route and persona of
  /// `ojd controller show`.
  static let fields: [GUIField] = [
    GUIField(
      command: ["controller", "show"],
      field: "serving.route",
      place: "Controllers > controller detail > Serving route fact"
    ),
    GUIField(
      command: ["controller", "show"],
      field: "serving.persona",
      place: "Controllers > controller detail > Published as fact"
    ),
  ]

  /// D10 rows, one entry per CLI group named in the row.
  ///
  /// `extension` is still the command name; D9 renames it `transport-extension` (task 17.1), and
  /// this entry follows the rename.
  static let places: [GUIPlace] =
    row(
      [["status"], ["extension"], ["permission"], ["service"]],
      area: "Status",
      mainMenu: "View > Status (Command-1)",
      statusItem: "status line, Open Window"
    )
    + row(
      [["controller"], ["virtual"], ["config", "show"]],
      area: "Controllers",
      mainMenu: "Controller menu",
      statusItem: "Controllers submenu"
    )
    + row(
      [["profile"], ["binding"]],
      area: "Profiles",
      mainMenu: "Profile menu, File > Import/Export Profile",
      statusItem: "Profiles submenu"
    )
    + row(
      [["record"], ["mod"]],
      area: "Library",
      mainMenu: "File > Install Record or Mod",
      statusItem: nil
    )
    + row([["access"]], area: "Access", mainMenu: nil, statusItem: "Grant Access")
    + row(
      [["log"], ["diagnose"], ["explain"]],
      area: "Activity",
      mainMenu: "File > Save Support Report, Save Activity Log; Help",
      statusItem: "Help submenu"
    )
    + row(
      [["setting"], ["update"]],
      area: "Settings window",
      mainMenu: "App > Settings",
      statusItem: "Settings"
    )

  private static func row(
    _ groups: [[String]],
    area: String,
    mainMenu: String?,
    statusItem: String?
  ) -> [GUIPlace] {
    groups.map { GUIPlace(prefix: $0, area: area, mainMenu: mainMenu, statusItem: statusItem) }
  }

  /// The entry that covers `path`, the longest matching prefix.
  static func place(for path: [String], in places: [GUIPlace] = places) -> GUIPlace? {
    places.filter { path.starts(with: $0.prefix) }.max { $0.prefix.count < $1.prefix.count }
  }

  /// The commands that run something (leaves) and have no GUI place.
  static func unmapped(in paths: [[String]], places: [GUIPlace] = places) -> [[String]] {
    let leaves = paths.filter { path in
      !paths.contains { $0.count > path.count && $0.starts(with: path) }
    }
    return leaves.filter { place(for: $0, in: places) == nil }
  }

  /// Entries that match no command, so a rename or removal cannot leave a stale row.
  static func stale(in paths: [[String]], places: [GUIPlace] = places) -> [GUIPlace] {
    places.filter { entry in !paths.contains { $0.starts(with: entry.prefix) } }
  }
}
