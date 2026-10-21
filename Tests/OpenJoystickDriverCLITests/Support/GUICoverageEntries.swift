import ArgumentParser
import Foundation

@testable import OpenJoystickDriverCLI

/// What performs one CLI item in the GUI, or why none does.
enum GUIDisposition: Equatable {
  /// A declaration in the GUI sources that performs the item. `GUISources` checks that it is
  /// declared and referenced.
  case symbol(String)
  /// The GUI place is not built yet. `task` is the tasks.md item that builds it, which the test
  /// requires to be unticked, so ticking the task forces this entry out.
  case pending(task: String, gap: String)
}

/// One CLI leaf (`option == nil`) or one behavior-changing option of a leaf, with its GUI place.
struct GUICoverageEntry: Equatable {
  /// The command path, such as `["controller", "rumble"]`.
  let command: [String]
  /// The long option, such as `--duration`; nil for the leaf itself.
  let option: String?
  let disposition: GUIDisposition

  var key: String {
    ([command.joined(separator: " ")] + (option.map { [$0] } ?? [])).joined(separator: " ")
  }
}

/// A leaf or option that a window cannot naturally perform (D10).
struct CLIOnlyItem: Equatable {
  /// The command path. For an option, nil means every command that has it.
  let command: [String]?
  let option: String?
  let reason: String
}

/// The per-leaf and per-option coverage of the real command tree. D10 says what a window cannot
/// naturally do; everything else names the GUI symbol that does it.
enum GUICoverageEntries {
  static let entries: [GUICoverageEntry] =
    status + controller + profile + binding + virtual + record + mod + access + system

  /// Leaves and options only a terminal or script performs. The D10 text names each of them, and
  /// `GUICoverageTests` checks that.
  static let cliOnly: [CLIOnlyItem] =
    [
      CLIOnlyItem(
        command: ["virtual", "feed"],
        option: nil,
        reason: "reads controller frames from standard input"
      ),
      CLIOnlyItem(
        command: ["service", "start"],
        option: nil,
        reason: "the app process hosts the service, so a window cannot start it"
      ),
      CLIOnlyItem(
        command: ["service", "stop"],
        option: nil,
        reason: "the app process hosts the service, so a window cannot stop it"
      ),
      CLIOnlyItem(
        command: ["service", "wait"],
        option: nil,
        reason: "a window exists only once the service listens, so nothing waits"
      ),
      CLIOnlyItem(
        command: ["help"],
        option: nil,
        reason: "terminal help"
      ),
    ]
    + ["--all", "--first-press", "--duration", "--output"].map {
      CLIOnlyItem(
        command: ["controller", "watch"],
        option: $0,
        reason: "scripting option of a stream a window shows continuously"
      )
    }
    + ["--json", "--plain", "--quiet", "--no-color", "--no-input", "--timeout"].map {
      CLIOnlyItem(command: nil, option: $0, reason: "output-only option")
    }
    + ["--force", "--dry-run"].map {
      CLIOnlyItem(
        command: nil,
        option: $0,
        reason: "a window confirms in a sheet and shows the result, so it needs neither"
      )
    }
    + ["--help", "--version"].map {
      CLIOnlyItem(command: nil, option: $0, reason: "terminal help and version")
    }

  // MARK: Entries

  private static let status = [
    leaf("status", "MainWindowProblemBanner"),
    leaf("permission list", "AccessPermissionRow"),
    leaf("permission request", "requestPermission"),
    leaf("transport-extension status", "refreshSystemExtensionSetup"),
    leaf("transport-extension activate", "startSystemExtensionSetup"),
    leaf("transport-extension deactivate", "uninstallSystemExtension"),
  ]

  private static let controller = [
    leaf("controller list", "ControllersView"),
    leaf("controller show", "ControllerDetailFacts"),
    leaf("controller watch", "InputTestLiveInputView"),
    leaf("controller capture", "ControllerPacketCapture"),
    option("controller capture", "--duration", "ControllerTimedActionSheet"),
    leaf("controller rumble", "rumbleCommand"),
    option("controller rumble", "--left", "InputTestRumbleMotorControl"),
    option("controller rumble", "--right", "InputTestRumbleMotorControl"),
    option("controller rumble", "--left-trigger", "InputTestRumbleMotorControl"),
    option("controller rumble", "--right-trigger", "InputTestRumbleMotorControl"),
    option("controller rumble", "--duration", "clampedRumbleDuration"),
    leaf("controller light", "applyColor"),
    option("controller light", "--color", "applyColor"),
    option("controller light", "--brightness", "applyBrightness"),
    leaf("controller player", "applyPlayerIndicator"),
    leaf("controller suspend", "suspendController"),
    leaf("controller resume", "resumeController"),
    leaf("controller disconnect", "disconnectWirelessController"),
    leaf("controller calibrate", "MotionCalibrationControls"),
    leaf("controller pair", "pairRemappingJoyCons"),
    option("controller pair", "--profile", "ProfileJoyConPairSheet"),
    leaf("controller unpair", "unpairRemappingJoyCons"),
    leaf("controller claim", "setControllerServer"),
    leaf("controller release", "setControllerServer"),
    leaf("config show", "ControllerTuningRows"),
    option("config show", "--controller", "ControllerTuningRows"),
  ]

  private static let profile = [
    leaf("profile list", "ProfilesView"),
    leaf("profile show", "ProfileEditorView"),
    leaf("profile create", "beginCreatingProfile"),
    option("profile create", "--controller", "ProfileControllerChoice"),
    option("profile create", "--app", "ProfileCreationFields"),
    option("profile create", "--virtual-gamepad", "ProfileOutputPolicyView"),
    option("profile create", "--physical-input", "ProfileOutputPolicyView"),
    leaf("profile duplicate", "ProfileDuplicateSheet"),
    leaf("profile rename", "updateMetadata"),
    leaf("profile delete", "deleteProfile"),
    leaf("profile activate", "activateProfile"),
    option("profile activate", "--allow-empty", "requestActivation"),
    leaf("profile deactivate", "deactivateProfile"),
    leaf("profile import", "chooseProfileToImport"),
    leaf("profile validate", "validateProfileFile"),
    leaf("profile export", "exportProfile"),
    option("profile export", "--output", "exportProfile"),
    leaf("profile get", "ProfileEditorView"),
    leaf("profile set", "updateMetadata"),
    leaf("profile edit", "ProfileEditorView"),
    leaf("profile recover", "recoverProfileIssue"),
  ]

  private static let binding = [
    leaf("binding list", "ProfileEditorView"),
    leaf("binding set", "addBinding"),
    option("binding set", "--behavior", "BindingBehaviorSheet"),
    option("binding set", "--pulse-ms", "pulseDurationMs"),
    option("binding set", "--deadzone", "AxisAdjustmentSheet"),
    option("binding set", "--gain", "AxisAdjustmentSheet"),
    option("binding set", "--invert", "AxisAdjustmentSheet"),
    option("binding set", "--response-curve", "AxisAdjustmentSheet"),
    option("binding set", "--digital-threshold", "AxisAdjustmentSheet"),
    option("binding set", "--turbo-rate", "turboRate"),
    option("binding set", "--turbo-duty", "turboDuty"),
    option("binding set", "--long-hold", "longHoldDuration"),
    option("binding set", "--double-tap", "doubleTapWindow"),
    option("binding set", "--actions-json", "ProfileAdditionalActionsView"),
    leaf("binding clear", "removeBinding"),
    option("binding clear", "--all", "removeAllAssignments"),
  ]

  private static let virtual = [
    leaf("virtual show", "VirtualHIDProfileOverrideView"),
    leaf("virtual set", "setVirtualHIDProfileOverride"),
    option("virtual set", "--unit", "VirtualHIDProfileScopeChoice"),
    leaf("virtual reset", "resetVirtualHIDProfileOverride"),
    option("virtual reset", "--all", "resetAllVirtualHIDProfileOverrides"),
    option("virtual reset", "--unit", "VirtualHIDProfileScopeChoice"),
    leaf("virtual export-mapping", "exportMapping"),
    option("virtual export-mapping", "--format", "ExportMappingAccessory"),
    leaf("virtual launch", "VirtualGamepadLaunch"),
    option("virtual launch", "--sdl-gamecontroller-backend", "chooseProgram"),
  ]

  private static let record = [
    leaf("record draft", "ControllerRecordDrafting"),
    option("record draft", "--duration", "ControllerTimedActionSheet"),
    leaf("record list", "LibraryListView"),
    option("record list", "--bundled", "LibraryScope"),
    leaf("record show", "LibraryRecordDetail"),
    leaf("record validate", "validateLibraryItem"),
    leaf("record install", "beginInstallRecord"),
    leaf("record remove", "removeRecord"),
    leaf("record test", "testSelectedRecord"),
    option("record test", "--packets", "chooseCapture"),
    option("record test", "--expect", "chooseExpectation"),
  ]

  private static let mod = [
    leaf("mod validate", "checkMod"),
    leaf("mod install", "beginInstallMod"),
    leaf("mod list", "LibraryModItem"),
    leaf("mod remove", "removeMod"),
  ]

  private static let access = [
    leaf("access status", "AccessAreaView"),
    leaf("access enable", "requestEnableEndpoint"),
    leaf("access disable", "disableEndpoint"),
    leaf("access list", "grantsSection"),
    leaf("access grant", "requestGrant"),
    option("access grant", "--token", "requestGrantToken"),
    option("access grant", "--origin", "AccessTokenDraft"),
    option("access grant", "--scope", "scopeChoices"),
    leaf("access revoke", "requestRevoke"),
    option("access revoke", "--scope", "partialRevoke"),
    leaf("access web enable", "requestEnableWeb"),
    option("access web enable", "--port", "webPort"),
    leaf("access web disable", "disableWeb"),
  ]

  private static let system = [
    leaf("setting list", "SettingsPreferencesModel"),
    leaf("setting get", "SettingsPreferencesModel"),
    leaf("setting set", "SettingsPreferencesModel"),
    leaf("setting reset", "resetSettings"),
    leaf("log show", "ActivityLogView"),
    option("log show", "--follow", "setFollowing"),
    option("log show", "--lines", "setLineCount"),
    leaf("log path", "showInFinder"),
    leaf("log export", "saveActivityLog"),
    option("log export", "--lines", "setLineCount"),
    leaf("diagnose", "ActivityDiagnosticsModel"),
    option("diagnose", "--output", "saveSupportReport"),
    option("diagnose", "--soak", "SoakTestSheet"),
    option("diagnose", "--interval-ms", "SoakTestSheet"),
    option("diagnose", "--rss-limit-mib", "SoakTestSheet"),
    option("diagnose", "--footprint-limit-mib", "SoakTestSheet"),
    leaf("update check", "checkForUpdates"),
    option("update check", "--prerelease", "setIncludePrereleaseUpdates"),
    leaf("explain", "ErrorCodeExplainerView"),
  ]

  // MARK: Builders

  private static func leaf(_ path: String, _ symbol: String) -> GUICoverageEntry {
    GUICoverageEntry(
      command: path.split(separator: " ").map(String.init),
      option: nil,
      disposition: .symbol(symbol)
    )
  }

  private static func option(
    _ path: String,
    _ option: String,
    _ symbol: String
  )
    -> GUICoverageEntry
  {
    GUICoverageEntry(
      command: path.split(separator: " ").map(String.init),
      option: option,
      disposition: .symbol(symbol)
    )
  }

  private static func pending(
    _ path: String,
    _ option: String,
    _ task: String,
    _ gap: String
  )
    -> GUICoverageEntry
  {
    GUICoverageEntry(
      command: path.split(separator: " ").map(String.init),
      option: option,
      disposition: .pending(task: task, gap: gap)
    )
  }
}

/// The GUI sources, scanned for the declarations the entries name.
enum GUISources {
  /// The repository root, from this file's place under `Tests/<target>/Support`.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  static let directories = ["Sources/OpenJoystickDriverPresentation", "Sources/OpenJoystickDriver"]

  /// Every GUI Swift file's text, joined.
  static let text: String = {
    var parts: [String] = []
    for directory in directories {
      let url = root.appendingPathComponent(directory)
      guard
        let files = FileManager.default.enumerator(
          at: url,
          includingPropertiesForKeys: nil
        )
      else { continue }
      for case let file as URL in files where file.pathExtension == "swift" {
        if let contents = try? String(contentsOf: file, encoding: .utf8) { parts.append(contents) }
      }
    }
    return parts.joined(separator: "\n")
  }()

  /// Whether `symbol` is declared in the GUI sources and used somewhere else there.
  static func isDeclaredAndReferenced(_ symbol: String) -> Bool {
    let name = NSRegularExpression.escapedPattern(for: symbol)
    let declaration =
      "\\b(func|case|var|let|struct|class|enum|actor|protocol)\\s+\(name)\\b"
    return count(of: declaration) >= 1 && count(of: "\\b\(name)\\b") >= 2
  }

  private static func count(of pattern: String) -> Int {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
    return expression.numberOfMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text)
    )
  }
}

/// The CLI surface read from the real command tree: leaves and the long names of their options and
/// flags, positional operands excluded.
struct CLISurfaceItem: Hashable {
  let command: [String]
  let option: String?

  var key: String {
    ([command.joined(separator: " ")] + (option.map { [$0] } ?? [])).joined(separator: " ")
  }
}

enum SurfaceError: Error { case noRoot }

enum CLISurface {
  static func items() throws -> [CLISurfaceItem] {
    let data = Data(OJDCommand._dumpHelp().utf8)
    let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let root = document?["command"] as? [String: Any] else { throw SurfaceError.noRoot }
    var items: [CLISurfaceItem] = []
    collect(root, path: [], into: &items)
    return items
  }

  private static func collect(
    _ command: [String: Any],
    path: [String],
    into items: inout [CLISurfaceItem]
  ) {
    let subcommands = command["subcommands"] as? [[String: Any]] ?? []
    if subcommands.isEmpty { items.append(CLISurfaceItem(command: path, option: nil)) }
    for argument in command["arguments"] as? [[String: Any]] ?? [] {
      guard argument["kind"] as? String != "positional",
        argument["shouldDisplay"] as? Bool ?? true,
        let names = argument["names"] as? [[String: Any]],
        let long = names.first(where: { $0["kind"] as? String == "long" })?["name"] as? String
      else { continue }
      items.append(CLISurfaceItem(command: path, option: "--\(long)"))
    }
    for subcommand in subcommands {
      collect(subcommand, path: path + [subcommand["commandName"] as? String ?? ""], into: &items)
    }
  }
}
