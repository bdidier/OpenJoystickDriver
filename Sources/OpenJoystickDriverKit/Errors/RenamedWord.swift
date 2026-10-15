import Foundation

/// A word that OpenJoystickDriver renamed to an OS-neutral word.
///
/// This is the one table of old words. The old word is not accepted anywhere; a refusal names the
/// new word through ``hint(localization:)``, for flags, values, and document fields alike.
public struct RenamedWord: Sendable, Equatable {
  /// Where the word is used.
  public enum Kind: Sendable, Equatable {
    /// A permission id on the command line or in a check id.
    case permissionID
    /// A field name in a document or an output.
    case field
    /// The `kind` of a publisher.
    case publisherKind
    /// A keyboard modifier name in a profile or binding document.
    case modifier
    /// A command-line flag of `command`, as typed, including its leading dashes.
    case flag(command: String)
    /// A top-level command group of `ojd`.
    case command
    /// A value of `ownership.physical` or `ownership.duplicateExposureRisk`.
    case physicalOwnership
    /// A value of `transportClaim` in a record output.
    case transportClaim
    /// The `kind` of a `--json` output document.
    case outputKind
    /// The id of a diagnose check.
    case checkID
    /// The `reason` of a controller's publication state.
    case publicationReason
    /// A property of the document kind that the schema file `in` defines, such as
    /// `report.schema.json` or `cli-output.schema.json#/$defs/diagnose`. Unlike `.field`, the
    /// word is refused only in that document, so a property of another document may keep the name.
    /// Add each row as one line, so that `Tests/RepositoryScripts/test_renamed_words.py` can read
    /// it and check that the schema no longer declares `old`.
    case documentField(in: String)
  }

  public let old: String
  public let new: String
  public let kind: Kind

  public init(old: String, new: String, kind: Kind) {
    self.old = old
    self.new = new
    self.kind = kind
  }

  /// Every renamed word of the access, publisher, application, and modifier rows.
  public static let all: [Self] = [
    Self(old: "input-monitoring", new: "input-read", kind: .permissionID),
    Self(old: "accessibility", new: "input-inject", kind: .permissionID),
    Self(old: "driver-extension", new: "usb-transport", kind: .permissionID),
    Self(old: "inputMonitoring", new: "inputRead", kind: .field),
    Self(old: "accessibility", new: "inputInject", kind: .field),
    Self(old: "identityKind", new: "publisher.kind", kind: .field),
    Self(old: "teamIdentifier", new: "publisher.id", kind: .field),
    Self(old: "bundleIdentifier", new: "appID", kind: .field),
    Self(old: "team", new: "signed", kind: .publisherKind),
    Self(old: "apple", new: "platform", kind: .publisherKind),
    Self(old: "command", new: "meta", kind: .modifier),
    Self(old: "option", new: "alt", kind: .modifier),
    Self(old: "--bundle", new: "--output", kind: .flag(command: "diagnose")),
    Self(old: "extension", new: "transport-extension", kind: .command),
    Self(old: "driverKitOwnedUSB", new: "ExtensionOwnedUsb", kind: .physicalOwnership),
    Self(old: "nativeGamepad", new: "SystemGamepad", kind: .physicalOwnership),
    Self(old: "nativeHIDVisible", new: "SystemHidVisible", kind: .physicalOwnership),
    Self(
      old: "usbExtension",
      new: "transportClaim",
      kind: .documentField(in: "cli-output.schema.json#/$defs/recordShow")
    ),
    Self(
      old: "usbExtension",
      new: "transportClaim",
      kind: .documentField(in: "cli-output.schema.json#/$defs/sharedRecordValidation")
    ),
    Self(
      old: "extension",
      new: "transportExtension",
      kind: .documentField(in: "cli-output.schema.json#/$defs/status")
    ),
    Self(old: "claims", new: "claimed", kind: .transportClaim),
    Self(old: "doesNotClaim", new: "unclaimed", kind: .transportClaim),
    Self(old: "DriverExtension", new: "TransportExtension", kind: .outputKind),
    Self(old: "extension-bundle", new: "transport-extension-bundle", kind: .checkID),
    Self(old: "extension-registration", new: "transport-extension-registration", kind: .checkID),
    Self(old: "nativeGamepad", new: "systemGamepad", kind: .publicationReason),
    Self(old: "macOSVersion", new: "osVersion", kind: .documentField(in: "report.schema.json")),
    Self(
      old: "appleGameControllerAudit",
      new: "systemGamepadAudit",
      kind: .documentField(in: "report.schema.json")
    ),
    Self(
      old: "appleExactDeviceCount",
      new: "systemExactDeviceCount",
      kind: .documentField(in: "report.schema.json")
    ),
    Self(
      old: "appleIdentifiers",
      new: "systemIdentifiers",
      kind: .documentField(in: "report.schema.json")
    ),
    Self(
      old: "skippedAppleDeviceCount",
      new: "skippedSystemDeviceCount",
      kind: .documentField(in: "report.schema.json")
    ),
    Self(
      old: "bundle",
      new: "output",
      kind: .documentField(in: "cli-output.schema.json#/$defs/diagnose")
    ),
  ]

  /// The renamed word for `old` in `kind`, or nil when `old` was not renamed there.
  public static func replacement(for old: String, kind: Kind) -> Self? {
    all.first { $0.kind == kind && $0.old == old }
  }

  /// The renamed property `old` of a document validated against the schema file `file`, or nil.
  public static func documentFieldReplacement(for old: String, in file: String) -> Self? {
    all.first { word in
      guard case .documentField(let location) = word.kind else { return false }
      return word.old == old && location.hasPrefix(file)
    }
  }

  /// The localized sentence that names the new word.
  public func hint(localization: Localization = Localization()) -> String {
    localization.formatted("cli.error.renamed_flag", arguments: [old, new])
  }

  /// The localized hints for the renamed words among `words`, each starting with a space, or an
  /// empty string when none of `words` was renamed.
  public static func hints(for words: [String], kind: Kind) -> String {
    let found = words.compactMap { replacement(for: $0, kind: kind) }
    guard !found.isEmpty else { return "" }
    let localization = Localization()
    return found.map { " " + $0.hint(localization: localization) }.joined()
  }
}
