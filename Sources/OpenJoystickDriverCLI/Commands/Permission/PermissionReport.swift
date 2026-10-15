import OpenJoystickDriverKit

/// A permission `ojd` reports. The raw values are the stable ids used on the command line,
/// in `--json`, and in `--plain` rows.
enum PermissionID: String, CaseIterable, Sendable {
  case inputRead = "input-read"
  case inputInject = "input-inject"
  case usbTransport = "usb-transport"

  /// The macOS privacy permissions that `ojd permission request` can ask for.
  static let requestable: [Self] = [.inputRead, .inputInject]

  /// The English name and purpose in `--json`, which are never localized.
  private var inventoryEntry: OJDPermissionRequirement {
    switch self {
    case .inputRead: .inputRead
    case .inputInject: .inputInject
    case .usbTransport: .usbTransport
    }
  }

  var name: String { inventoryEntry.name }

  var purpose: String { inventoryEntry.purpose }

  var localizedName: String {
    switch self {
    case .inputRead: CLILocalized.text("cli.permission.name.input_read")
    case .inputInject: CLILocalized.text("cli.permission.name.input_inject")
    case .usbTransport: CLILocalized.text("cli.permission.name.usb_transport")
    }
  }

  var localizedPurpose: String {
    switch self {
    case .inputRead: CLILocalized.text("cli.permission.purpose.input_read")
    case .inputInject: CLILocalized.text("cli.permission.purpose.input_inject")
    case .usbTransport: CLILocalized.text("cli.permission.purpose.usb_transport")
    }
  }

  /// Where the user allows this permission in System Settings.
  var localizedSettingsPane: String {
    switch self {
    case .inputRead:
      CLILocalized.text(
        "cli.permission.pane.input_read"
      )
    case .inputInject:
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

    init(_ permission: PermissionID, state: PermissionManager.AccessState) {
      id = permission.rawValue
      name = permission.name
      self.state = state
      purpose = permission.purpose
    }
  }

  let permissions: [Entry]

  init(snapshot: PermissionManager.Snapshot, extensionStatus: ExtensionStatus) {
    let driverState: PermissionManager.AccessState
    switch extensionStatus.registration {
    case .active: driverState = .granted
    case .inactive: driverState = .denied
    case .absent, .unavailable: driverState = .unknown
    }
    permissions = [
      Entry(.inputRead, state: snapshot.inputRead),
      Entry(.inputInject, state: snapshot.inputInject),
      Entry(.usbTransport, state: driverState),
    ]
  }

  func state(of permission: PermissionID) -> PermissionManager.AccessState {
    permissions.first { $0.id == permission.rawValue }?.state ?? .unknown
  }

  var plainRows: [[String]] { permissions.map { [$0.id, $0.state.rawValue] } }
}
