import Foundation

/// A word that OpenJoystickDriver renamed to an OS-neutral word.
///
/// The old word is not accepted anywhere. A refusal names the new word through ``hint(localization:)``.
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
  ]

  /// The renamed word for `old` in `kind`, or nil when `old` was not renamed there.
  public static func replacement(for old: String, kind: Kind) -> Self? {
    all.first { $0.kind == kind && $0.old == old }
  }

  /// The localized sentence that names the new word.
  public func hint(localization: Localization = Localization()) -> String {
    localization.formatted("renamed_word.hint", arguments: [old, new])
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
