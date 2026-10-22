import Foundation

/// The client that holds a USB interface open exclusively, as the interface's `UsbExclusiveOwner`
/// registry property names it.
///
/// A user-space client is named `pid <number>, <process name>`; the kernel truncates the process
/// name to 16 characters. A kernel driver is named by its class, such as `AppleUSB20Hub`, and
/// carries no process ID.
public struct USBExclusiveOwner: Codable, Equatable, Sendable {
  /// The owning process, or nil when a kernel driver holds the interface.
  public let processID: Int32?
  /// The process name or the kernel driver class.
  public let name: String

  public init(processID: Int32?, name: String) {
    self.processID = processID
    self.name = name
  }

  /// The user-facing sentence that names the holder and says OpenJoystickDriver serves the
  /// controller when the holder releases it.
  /// `localize` returns the catalog text of a key.
  public static func heldMessage(
    for owner: Self?,
    localize: (String) -> String
  ) -> String {
    guard let owner else { return localize("status.controllerOwner.unnamed") }
    guard let processID = owner.processID else {
      return String(format: localize("status.controllerOwner.nameOnly"), owner.name)
    }
    return String(
      format: localize("status.controllerOwner.named"),
      owner.name,
      String(processID)
    )
  }

  /// Parses the registry value; nil for an empty value, which names no owner.
  public init?(registryValue: String) {
    let value = registryValue.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else { return nil }
    let prefix = "pid "
    if value.hasPrefix(prefix), let comma = value.firstIndex(of: ","),
      let processID = Int32(value[value.index(value.startIndex, offsetBy: prefix.count)..<comma]),
      case let name = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces),
      !name.isEmpty
    {
      self.init(processID: processID, name: name)
    } else {
      self.init(processID: nil, name: value)
    }
  }
}
