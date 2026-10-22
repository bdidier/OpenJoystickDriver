import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `PROFILE` argument: a profile UUID, or a profile name matched exactly but without regard
/// to case.
struct ProfileSelector: ExpressibleByArgument, Equatable, Sendable {
  let text: String

  init?(argument: String) {
    guard !argument.isEmpty else { return nil }
    text = argument
  }

  /// The one profile this selector names.
  ///
  /// Throws a failure with exit code 1 when no profile or several profiles match.
  func resolve(in profiles: [RemappingProfile]) throws -> RemappingProfile {
    if let id = UUID(uuidString: text), let profile = profiles.first(where: { $0.id == id }) {
      return profile
    }
    let matches = profiles.filter { $0.name.caseInsensitiveCompare(text) == .orderedSame }
    if matches.count == 1, let profile = matches.first { return profile }
    guard matches.isEmpty else {
      let message = CLILocalized.format(
        "cli.profile.group.selectorAmbiguous",
        text,
        matches.count
      )
      let lines = matches.map { "  \($0.id.uuidString)  \($0.name)" }
      throw CLIFailure(.notFound, ([message] + lines).joined(separator: "\n"))
    }
    throw CLIFailure(
      .notFound,
      CLILocalized.format(
        "cli.profile.group.selectorNotFound",
        text
      )
    )
  }

  /// Reads the profiles from the service and resolves this selector.
  func resolve(
    with client: ApplicationServiceClient
  ) async throws -> (RemappingProfile, ApplicationServiceRemappingSnapshotPayload) {
    let snapshot = try await client.getRemappingSnapshot()
    return (try resolve(in: snapshot.profiles), snapshot)
  }
}

/// The shared `PROFILE` argument help.
let profileArgumentHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.profile.group.argument"
  ),
  valueName: "profile"
)

/// One profile in `--json` output.
struct ProfileSummary: Encodable, Equatable {
  let id: String
  let name: String
  let controller: String
  let scope: String
  let active: Bool
  let bindings: Int

  init(_ profile: RemappingProfile, snapshot: ApplicationServiceRemappingSnapshotPayload) {
    id = profile.id.uuidString
    name = profile.name
    controller = deviceIdentity(
      vendorID: Int(profile.device.vendorID),
      productID: Int(profile.device.productID)
    )
    scope = ProfileText.scope(profile.applicationScope)
    active = snapshot.activeProfiles.contains { $0.profileID == profile.id }
    bindings = profile.bindings.count
  }

  var row: [String] { [id, name, controller, scope, String(active)] }

  var line: String {
    let marker = active ? "  " + CLILocalized.text("cli.profile.group.activeMarker") : ""
    return "\(id)  \(name)  \(controller)  \(scope)\(marker)"
  }
}

extension RemappingProfile {
  /// Validates the profile and turns a validation error into an invalid-profile failure.
  func validatedForCLI() throws -> Self {
    do { try validate() } catch {
      throw CLIFailure(
        .invalidProfile,
        CLILocalized.format(
          "cli.profile.group.invalid",
          error.localizedDescription
        )
      )
    }
    return self
  }
}

extension RemappingVirtualGamepadPolicy: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `tap-on-press`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingPhysicalInputPolicy: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `tap-on-press`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingBindingBehavior: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `tap-on-press`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingResponseCurve: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case, such as `tap-on-press`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

extension RemappingMotionCalibrationCommand: ExpressibleByArgument {
  /// The lowercase kebab-case spelling of a case.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}
