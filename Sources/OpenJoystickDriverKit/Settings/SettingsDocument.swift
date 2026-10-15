import Foundation

/// The contents of one `Settings.json` layer; every setting is optional, and a setting a layer
/// leaves out falls through to the layer below it.
///
/// See `Resources/Schemas/settings.schema.json`.
public struct SettingsDocument: Equatable, Sendable {
  /// The `kind` of the file.
  public static let kind = "Settings"

  /// Which events post a notification.
  public struct Notify: Equatable, Sendable {
    public var controllerConnected: Bool?
    public var controllerDisconnected: Bool?
    public var profileActivated: Bool?
    public var profileDeactivated: Bool?
    public var sounds: Bool?

    public init() {}
  }

  /// How update checks behave.
  public struct Updates: Equatable, Sendable {
    public var includePrereleases: Bool?

    public init() {}
  }

  /// Internal state, not a setting: true after the user turned launch at login off through the
  /// app or `ojd setting`, so the app does not register itself on its next start. The public key
  /// `launchAtLogin` is read from and written to the macOS login item, which stays the source of
  /// truth; a change made in System Settings does not update this field.
  public var launchAtLoginOptOut: Bool?
  public var notify = Notify()
  public var updates = Updates()
  public var developerTools: Bool?

  public init() {}

  /// The stored value of `key`, or nil when this layer leaves it out.
  ///
  /// `launchAtLogin` here is the opposite of the stored `launchAtLoginOptOut`; it is not the
  /// state of the login item, which only macOS knows.
  public subscript(key: ApplicationSettingKey) -> Bool? {
    get {
      switch key {
      case .launchAtLogin: launchAtLoginOptOut.map { !$0 }
      case .notifyControllerConnected: notify.controllerConnected
      case .notifyControllerDisconnected: notify.controllerDisconnected
      case .notifyProfileActivated: notify.profileActivated
      case .notifyProfileDeactivated: notify.profileDeactivated
      case .notifySounds: notify.sounds
      case .updatesIncludePrereleases: updates.includePrereleases
      case .developerTools: developerTools
      }
    }
    set {
      switch key {
      case .launchAtLogin: launchAtLoginOptOut = newValue.map { !$0 }
      case .notifyControllerConnected: notify.controllerConnected = newValue
      case .notifyControllerDisconnected: notify.controllerDisconnected = newValue
      case .notifyProfileActivated: notify.profileActivated = newValue
      case .notifyProfileDeactivated: notify.profileDeactivated = newValue
      case .notifySounds: notify.sounds = newValue
      case .updatesIncludePrereleases: updates.includePrereleases = newValue
      case .developerTools: developerTools = newValue
      }
    }
  }

  /// This layer with every setting that `upper` stores replacing the one here.
  public func overlaid(by upper: Self) -> Self {
    var merged = self
    for key in ApplicationSettingKey.allCases {
      if let value = upper[key] { merged[key] = value }
    }
    return merged
  }
}

/// A header that is not the supported `apiVersion` and `kind`; the store names the file.
struct SettingsHeaderProblem: Error, Equatable, Sendable { let problem: DocumentHeaderProblem }

extension SettingsDocument.Notify: Codable {
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case controllerConnected, controllerDisconnected, profileActivated, profileDeactivated, sounds
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    controllerConnected = try container.decodeIfPresent(Bool.self, forKey: .controllerConnected)
    controllerDisconnected = try container.decodeIfPresent(
      Bool.self,
      forKey: .controllerDisconnected
    )
    profileActivated = try container.decodeIfPresent(Bool.self, forKey: .profileActivated)
    profileDeactivated = try container.decodeIfPresent(Bool.self, forKey: .profileDeactivated)
    sounds = try container.decodeIfPresent(Bool.self, forKey: .sounds)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(controllerConnected, forKey: .controllerConnected)
    try container.encodeIfPresent(controllerDisconnected, forKey: .controllerDisconnected)
    try container.encodeIfPresent(profileActivated, forKey: .profileActivated)
    try container.encodeIfPresent(profileDeactivated, forKey: .profileDeactivated)
    try container.encodeIfPresent(sounds, forKey: .sounds)
  }
}

extension SettingsDocument.Updates: Codable {
  private enum CodingKeys: String, CodingKey, CaseIterable { case includePrereleases }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    includePrereleases = try container.decodeIfPresent(Bool.self, forKey: .includePrereleases)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(includePrereleases, forKey: .includePrereleases)
  }
}

extension SettingsDocument: Codable {
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case apiVersion, kind, launchAtLoginOptOut, notify, updates, developerTools
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      throw SettingsHeaderProblem(problem: problem)
    }
    try decoder.rejectUnknownKeys(CodingKeys.self)
    launchAtLoginOptOut = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginOptOut)
    notify = try container.decodeIfPresent(Notify.self, forKey: .notify) ?? Notify()
    updates = try container.decodeIfPresent(Updates.self, forKey: .updates) ?? Updates()
    developerTools = try container.decodeIfPresent(Bool.self, forKey: .developerTools)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encodeIfPresent(launchAtLoginOptOut, forKey: .launchAtLoginOptOut)
    if notify != Notify() { try container.encode(notify, forKey: .notify) }
    if updates != Updates() { try container.encode(updates, forKey: .updates) }
    try container.encodeIfPresent(developerTools, forKey: .developerTools)
  }
}
