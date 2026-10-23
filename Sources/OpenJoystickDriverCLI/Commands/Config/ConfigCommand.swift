import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ConfigCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: CLILocalized.text("cli.config.group.abstract"),
    discussion: CLILocalized.text("cli.config.group.discussion"),
    subcommands: [ConfigShowCommand.self, ConfigSetCommand.self, ConfigUnsetCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

struct ConfigShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text("cli.config.show.abstract"),
    discussion: CLILocalized.text("cli.config.show.discussion")
  )

  /// One tuning value and the layer that set it. `value` is nil while only the driver default
  /// applies, which the driver picks itself. `families` lists the protocol families that read the
  /// key; it is set for a tuning key only without `--controller`.
  struct Value: Encodable, Equatable {
    let key: String
    let value: Double?
    let layer: String
    let families: [String]?
  }

  /// The `--json` result. `controller` is absent without `--controller`.
  struct Result: Encodable, Equatable {
    let controller: String?
    let profile: String?
    let defaultsFile: String
    let defaultsProblem: String?
    let values: [Value]
  }

  @Option(
    name: .customLong("controller"),
    help: ArgumentHelp(CLILocalized.text("cli.config.show.controller"), valueName: "VVVV:PPPP")
  )
  var controller: ControllerModelID?

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      let result = try Self.result(
        for: controller,
        in: set,
        activeProfile: await Self.activeProfile(for: controller)
      )
      if controller == nil {
        switch await Self.unreadDefaults(in: set) {
        case .ran(let keys):
          for key in keys {
            CLIOutput.stderr(
              CLILocalized.format(
                "cli.config.show.unread",
                key.rawValue,
                Self.families(reading: key, in: set).joined(separator: ", ")
              )
            )
          }
        case .skipped(let serviceRunning):
          CLIOutput.stderr(
            CLILocalized.text(
              serviceRunning
                ? "cli.config.show.unreadSkippedNoController"
                : "cli.config.show.unreadSkippedNoService"
            )
          )
        }
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain(
          result.values.map {
            [$0.key, Self.text($0.value, of: $0.key), CommandLineName.kebab($0.layer)]
              + [$0.families?.joined(separator: ",")].compactMap { $0 }
          }
        )
      case .human:
        if let problem = result.defaultsProblem {
          CLIOutput.stderr(
            CLILocalized.format("cli.config.show.defaultsIgnored", result.defaultsFile, problem)
          )
        }
        let width = result.values.map(\.key.count).max() ?? 0
        for item in result.values {
          let key = item.key.padding(toLength: width, withPad: " ", startingAt: 0)
          let families = item.families.map {
            "  " + CLILocalized.format("cli.config.show.readBy", $0.joined(separator: ", "))
          }
          CLIOutput.stdout(
            "\(key)  \(Self.text(item.value, of: item.key))  (\(CommandLineName.kebab(item.layer)))"
              + (families ?? "")
          )
        }
      }
    }
  }

  /// The profile that is active for `model`, or nil without `--controller`, without a running
  /// service, or without an active profile for that model. The service is optional here, so
  /// `config show` keeps working offline and then shows no profile rows.
  private static func activeProfile(for model: ControllerModelID?) async -> RemappingProfile? {
    guard let model,
      let snapshot = try? await ServiceConnection.request({ try await $0.getRemappingSnapshot() }),
      let active = snapshot.activeProfiles.routingActiveProfile(
        vendorID: model.vendorID,
        productID: model.productID
      )
    else { return nil }
    return snapshot.profiles.first { $0.id == active.profileID }
  }

  /// The protocol families with a record whose driver reads `key`, sorted.
  static func families(reading key: ControllerTuning.Key, in set: ControllerRecordSet) -> [String] {
    Set(set.records.values.filter { $0.reads(key) }.map(\.family)).sorted()
  }

  /// The outcome of checking the keys `all.patch.json` sets against the connected controllers.
  private enum UnreadCheck {
    /// The keys no connected controller reads, in key order.
    case ran([ControllerTuning.Key])
    /// The check could not name the connected controllers.
    case skipped(serviceRunning: Bool)
  }

  /// Checks the keys `all.patch.json` sets against the connected controllers. The service is asked
  /// only when some record ignores a key `all.patch.json` sets. Without a running service or a
  /// connected controller the check is skipped, so the caller can say so instead of looking clean.
  private static func unreadDefaults(in set: ControllerRecordSet) async -> UnreadCheck {
    let keys = ControllerTuning.Key.allCases.filter { key in
      set.defaults?.tuning.setKeys.contains(key) == true
        && set.records.values.contains { !$0.reads(key) }
    }
    guard !keys.isEmpty else { return .ran([]) }
    guard let status = try? await ServiceConnection.request({ try await $0.getStatus() }) else {
      return .skipped(serviceRunning: false)
    }
    guard !status.connectedDevices.isEmpty else { return .skipped(serviceRunning: true) }
    return .ran(unreadKeys(keys, in: set, connected: status.connectedDevices))
  }

  /// The members of `keys` that no record of a `connected` controller reads. A controller without
  /// a record reads none, because only a record carries a tuning.
  static func unreadKeys(
    _ keys: [ControllerTuning.Key],
    in set: ControllerRecordSet,
    connected: [ApplicationServiceDeviceDescription]
  ) -> [ControllerTuning.Key] {
    let records = connected.compactMap {
      set.records[ControllerModelID(vendorID: $0.vendorID, productID: $0.productID)]
    }
    return keys.filter { key in !records.contains { $0.reads(key) } }
  }

  /// Each tuning key with its effective value and layer: the controller's record when one is
  /// named, else the global defaults over the driver defaults. The active profile adds one
  /// `profile` row for each stick mapping's `innerDeadzone`, keyed as `profile get` names it.
  /// The profile value calibrates that mapping's output and does not override `stickDeadzone`.
  static func result(
    for model: ControllerModelID?,
    in set: ControllerRecordSet,
    activeProfile: RemappingProfile? = nil
  ) throws -> Result {
    let defaults = set.defaults
    let effective: [ControllerTuningValue]
    if let model {
      guard let record = set.records[model] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.record.show.notFound", model.description)
        )
      }
      effective = record.tuningValues
    } else {
      effective = set.defaultTuningValues
    }
    let values = effective.map { entry in
      Value(
        key: entry.key.rawValue,
        value: entry.value,
        layer: entry.layer.rawValue,
        families: model == nil ? Self.families(reading: entry.key, in: set) : nil
      )
    }
    let profileValues = (activeProfile?.stickMappings ?? []).enumerated().map { index, mapping in
      Value(
        key: "stickMappings.\(index).tuning.innerDeadzone",
        value: mapping.tuning.innerDeadzone,
        layer: ControllerRecordLayer.profile.rawValue,
        families: nil
      )
    }
    return Result(
      controller: model?.description,
      profile: activeProfile?.name,
      defaultsFile: (defaults?.url ?? ControllerDefaults.userFile).path,
      defaultsProblem: defaults?.problem,
      values: values + profileValues
    )
  }

  static func text(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }

  /// `value`, or what applies to `key` while no layer sets it.
  static func text(_ value: Double?, of key: String) -> String {
    value.map(text)
      ?? CLILocalized.text(
        ControllerTuning.Key(rawValue: key)?.hasDriverValue == true
          ? "tuning.driverDefault" : "status.notSet"
      )
  }
}
