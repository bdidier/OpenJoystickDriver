import Foundation
import IOKit
import IOKit.hid

private let permissionPollNanoseconds: UInt64 = 1_000_000_000
// TCC needs a short run-loop turn to register the application after the
// Input Monitoring request.  Asking for Accessibility immediately afterwards
// can make macOS skip adding the app to the Input Monitoring list altogether.
private let inputReadRegistrationDelayNanoseconds: UInt64 = 600_000_000

/// Manages the macOS HID permissions used by OpenJoystickDriver.
public actor PermissionManager {
  public enum Requirement: String, Codable, Sendable, Equatable {
    case inputRead
    case inputInject
  }

  public enum AccessState: String, Codable, Sendable, Equatable, CustomStringConvertible {
    case granted
    case denied
    case unknown

    public init(status: String) {
      let token = status.split { $0.isWhitespace }.last
      self = token.flatMap { Self(rawValue: String($0).lowercased()) } ?? .unknown
    }

    public var description: String { rawValue }

    public var label: String {
      switch self {
      case .granted: return "[OK]"
      case .denied: return "[DENIED]"
      case .unknown: return "[UNKNOWN]"
      }
    }
  }

  /// Current permission states for physical input and virtual HID publication.
  public struct Snapshot: Codable, Sendable, Equatable {
    public let inputRead: AccessState
    public let inputInject: AccessState

    public init(inputRead: AccessState, inputInject: AccessState) {
      self.inputRead = inputRead
      self.inputInject = inputInject
    }

    public var isReady: Bool { inputRead == .granted && inputInject == .granted }
  }

  public private(set) var inputReadState: AccessState = .unknown
  public private(set) var inputInjectState: AccessState = .unknown
  private(set) var pollingTask: Task<Void, Never>?

  public init() {}

  nonisolated public static func currentInputReadAccessState() -> AccessState {
    accessState(for: kIOHIDRequestTypeListenEvent)
  }

  /// IOHIDUserDevice creation is authorized through the post-event TCC service.
  nonisolated public static func currentInputInjectAccessState() -> AccessState {
    accessState(for: kIOHIDRequestTypePostEvent)
  }

  nonisolated private static func accessState(for requestType: IOHIDRequestType) -> AccessState {
    switch IOHIDCheckAccess(requestType) {
    case kIOHIDAccessTypeGranted: return .granted
    case kIOHIDAccessTypeDenied: return .denied
    default: return .unknown
    }
  }

  public func checkAccess() -> Snapshot {
    Snapshot(
      inputRead: Self.currentInputReadAccessState(),
      inputInject: Self.currentInputInjectAccessState()
    )
  }

  @discardableResult
  public func refreshAccessState() -> Snapshot {
    let snapshot = checkAccess()
    updateState(
      name: "Input read",
      previous: inputReadState,
      current: snapshot.inputRead
    )
    updateState(
      name: "Input inject",
      previous: inputInjectState,
      current: snapshot.inputInject
    )
    inputReadState = snapshot.inputRead
    inputInjectState = snapshot.inputInject
    return snapshot
  }

  /// Requests every HID permission that is not already granted.
  ///
  /// Input Monitoring is deliberately requested before Accessibility. macOS
  /// registers the caller in the Input Monitoring list asynchronously; a
  /// short delay lets that registration complete before the second request.
  /// Return values from IOHIDRequestAccess are deliberately ignored. The
  /// authoritative post-request state comes from IOHIDCheckAccess.
  @discardableResult
  public func requestRequiredAccess() async -> Snapshot {
    var snapshot = checkAccess()
    if snapshot.inputRead != .granted {
      await requestAccessOnMainActor(kIOHIDRequestTypeListenEvent)
      try? await Task.sleep(nanoseconds: inputReadRegistrationDelayNanoseconds)
      snapshot = checkAccess()
    }
    if snapshot.inputInject != .granted {
      await requestAccessOnMainActor(kIOHIDRequestTypePostEvent)
    }
    return refreshAccessState()
  }

  /// Requests one permission from the row that owns that permission.
  ///
  /// The request result is never treated as a grant; the returned snapshot is
  /// read back through `IOHIDCheckAccess`.
  @discardableResult
  public func requestAccess(_ requirement: Requirement) async -> Snapshot {
    let snapshot = checkAccess()
    switch requirement {
    case .inputRead where snapshot.inputRead != .granted:
      await requestAccessOnMainActor(kIOHIDRequestTypeListenEvent)
      try? await Task.sleep(nanoseconds: inputReadRegistrationDelayNanoseconds)
    case .inputInject where snapshot.inputInject != .granted:
      await requestAccessOnMainActor(kIOHIDRequestTypePostEvent)
    default: break
    }
    return refreshAccessState()
  }

  /// TCC request calls are initiated on the app's main actor.  Besides matching
  /// AppKit's user-initiated permission flow, this gives macOS a live run loop
  /// for registering the bundle before the settings deep link is opened.
  private func requestAccessOnMainActor(_ requestType: IOHIDRequestType) async {
    await MainActor.run { _ = IOHIDRequestAccess(requestType) }
  }

  public func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: permissionPollNanoseconds)
        guard let self else { break }
        await self.refreshAccessState()
      }
    }
  }

  public func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  private func updateState(name: String, previous: AccessState, current: AccessState) {
    guard previous != current else { return }
    print("[PermissionManager] \(name) state changed: \(previous) -> \(current)")
  }
}

public struct OJDPermissionRequirement: Sendable, Equatable {
  public let name: String
  public let owner: String
  public let purpose: String
  public let requested: Bool

  public init(name: String, owner: String, purpose: String, requested: Bool) {
    self.name = name
    self.owner = owner
    self.purpose = purpose
    self.requested = requested
  }

  public static let inputRead = Self(
    name: "Input read",
    owner: "OpenJoystickDriver app",
    purpose: "Read input from physical controllers",
    requested: true
  )
  public static let inputInject = Self(
    name: "Input inject",
    owner: "OpenJoystickDriver app",
    purpose: "Publish virtual controller output",
    requested: true
  )
  public static let usbTransport = Self(
    name: "USB transport",
    owner: "OpenJoystickDriver app",
    purpose: "Own entitlement-restricted raw USB interfaces; not a privacy permission",
    requested: true
  )

  public static let inventory = [inputRead, inputInject, usbTransport]
}
