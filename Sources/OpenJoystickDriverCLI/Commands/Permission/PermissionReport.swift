import OpenJoystickDriverKit

/// A permission `ojd` reports. The raw values are the ids in `--json`; the command line and
/// `--plain` rows spell them in lowercase kebab-case, such as `input-read`.
enum PermissionID: String, CaseIterable, Sendable {
  case inputRead = "InputRead"
  case inputInject = "InputInject"
  case usbTransport = "USBTransport"
  case postEvent = "PostEvent"

  /// The id on the command line and in `--plain` rows.
  var commandLineName: String { CommandLineName.kebab(rawValue) }

  /// The macOS privacy permissions that `ojd permission request` can ask for.
  static let requestable: [Self] = [.inputRead, .inputInject]

  /// The English name and purpose in `--json`, which are never localized.
  private var inventoryEntry: OJDPermissionRequirement {
    switch self {
    case .inputRead: .inputRead
    case .inputInject: .inputInject
    case .usbTransport: .usbTransport
    case .postEvent: .postEvent
    }
  }

  var name: String { inventoryEntry.name }

  var purpose: String { inventoryEntry.purpose }

  var localizedName: String {
    switch self {
    case .inputRead: CLILocalized.text("cli.permission.name.input_read")
    case .inputInject: CLILocalized.text("cli.permission.name.input_inject")
    case .usbTransport: CLILocalized.text("cli.permission.name.usb_transport")
    case .postEvent: CLILocalized.text("cli.permission.name.post_event")
    }
  }

  var localizedPurpose: String {
    switch self {
    case .inputRead: CLILocalized.text("cli.permission.purpose.input_read")
    case .inputInject: CLILocalized.text("cli.permission.purpose.input_inject")
    case .usbTransport: CLILocalized.text("cli.permission.purpose.usb_transport")
    case .postEvent: CLILocalized.text("cli.permission.purpose.post_event")
    }
  }

  /// Where the user allows this permission in System Settings.
  var localizedSettingsPane: String {
    switch self {
    case .inputRead:
      CLILocalized.text(
        "cli.permission.pane.input_read"
      )
    case .inputInject, .postEvent:
      CLILocalized.text("cli.permission.pane.input_inject")
    case .usbTransport:
      CLILocalized.text(
        "cli.permission.pane.usb_transport"
      )
    }
  }
}

/// The `ojd permission request --json` result, and the items of `ojd permission list --json`.
struct PermissionReport: Encodable, Equatable {
  struct Entry: Encodable, Equatable {
    let id: String
    let name: String
    let state: PermissionManager.AccessState
    let purpose: String
    /// Whether the active profile needs the permission. Only `PostEvent` has it, and only when
    /// the service reported the profiles.
    let requiredByActiveProfile: Bool?

    init(
      _ permission: PermissionID,
      state: PermissionManager.AccessState,
      requiredByActiveProfile: Bool? = nil
    ) {
      id = permission.rawValue
      name = permission.name
      self.state = state
      purpose = permission.purpose
      self.requiredByActiveProfile = requiredByActiveProfile
    }
  }

  let permissions: [Entry]

  /// The Post Event access the service reports, and whether the active profile needs it.
  struct PostEvent: Equatable {
    let state: PermissionManager.AccessState
    let requiredByActiveProfile: Bool?
  }

  /// `postEvent` is nil for a report that does not cover Post Event access.
  init(
    snapshot: PermissionManager.Snapshot,
    extensionStatus: ExtensionStatus,
    postEvent: PostEvent? = nil
  ) {
    let driverState: PermissionManager.AccessState
    switch extensionStatus.registration {
    case .active: driverState = .granted
    case .inactive: driverState = .denied
    case .absent, .unavailable: driverState = .unknown
    }
    var entries = [
      Entry(.inputRead, state: snapshot.inputRead),
      Entry(.inputInject, state: snapshot.inputInject),
      Entry(.usbTransport, state: driverState),
    ]
    if let postEvent {
      entries.append(
        Entry(
          .postEvent,
          state: postEvent.state,
          requiredByActiveProfile: postEvent.requiredByActiveProfile
        )
      )
    }
    permissions = entries
  }

  func state(of permission: PermissionID) -> PermissionManager.AccessState {
    permissions.first { $0.id == permission.rawValue }?.state ?? .unknown
  }

  /// One row per permission: id and state, plus `required` or `not-required` for Post Event
  /// access when the service reported the profiles.
  var plainRows: [[String]] {
    permissions.map { entry in
      var row = [CommandLineName.kebab(entry.id), CommandLineName.kebab(entry.state.rawValue)]
      if let required = entry.requiredByActiveProfile {
        row.append(required ? "required" : "not-required")
      }
      return row
    }
  }
}
