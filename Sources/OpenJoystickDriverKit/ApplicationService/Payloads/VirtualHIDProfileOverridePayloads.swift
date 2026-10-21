import Foundation

/// Arguments of `setVirtualHIDProfileOverride`: the controller reference, the requested
/// profile's raw identifier, such as `Generic`, and whether the override is for the selected
/// unit only (see ``ControllerPortKey``) instead of its model.
public struct LocalServiceRPCVirtualHIDProfileOverrideArguments: Codable, Sendable {
  public let controller: ControllerReference
  public let profile: String
  public let unit: Bool

  public init(
    controller: ControllerReference,
    profile: String,
    unit: Bool = false
  ) {
    self.controller = controller
    self.profile = profile
    self.unit = unit
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    controller = try container.decode(ControllerReference.self, forKey: .controller)
    profile = try container.decode(String.self, forKey: .profile)
    unit = try container.decode(Bool.self, forKey: .unit)
  }
}

/// Arguments of `resetVirtualHIDProfileOverride`: the controller reference and whether to reset
/// the selected unit's override instead of its model's.
public struct LocalServiceRPCVirtualHIDProfileOverrideResetArguments: Codable, Sendable {
  public let controller: ControllerReference
  public let unit: Bool

  public init(controller: ControllerReference, unit: Bool = false) {
    self.controller = controller
    self.unit = unit
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    controller = try container.decode(ControllerReference.self, forKey: .controller)
    unit = try container.decode(Bool.self, forKey: .unit)
  }
}

/// Why a virtual HID profile override request did not take full effect.
///
/// Encoded as `{"code": String, "detail": String?}`; only `activationFailed` carries a detail.
public enum VirtualHIDProfileOverrideFailure: Codable, Equatable, Sendable {
  /// The requested profile identifier names no profile. Nothing was stored.
  case unknownProfile
  /// No connected controller matches the reference, a port reference or a unit request matches
  /// more than one, a unit request selects a controller without a port key, or the selected
  /// controller disconnected during the request.
  /// The stored override is unchanged, except when the controller disconnected after every
  /// retarget succeeded.
  case controllerNotFound
  /// The override is stored, but the controller cannot satisfy it, so automatic selection runs.
  case overrideRejectedByController
  /// A replacement backend failed or timed out; the prior stored value is restored and every
  /// retargeted controller of the model returns to it. The detail also reports a failed restore.
  case activationFailed(detail: String)
  /// The override is stored, but no automatic virtual output is live to apply it to.
  case outputDisabled
  /// The service stopped before or during the request. The stored override is unchanged.
  case serverStopped
  /// The stored overrides cannot be read or written. Nothing was stored.
  case persistenceFailed

  /// The wire identifier of the failure.
  public var code: String {
    switch self {
    case .unknownProfile: "unknownProfile"
    case .controllerNotFound: "controllerNotFound"
    case .overrideRejectedByController: "overrideRejectedByController"
    case .activationFailed: "activationFailed"
    case .outputDisabled: "outputDisabled"
    case .serverStopped: "serverStopped"
    case .persistenceFailed: "persistenceFailed"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case detail
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let code = try container.decode(String.self, forKey: .code)
    switch code {
    case "unknownProfile": self = .unknownProfile
    case "controllerNotFound": self = .controllerNotFound
    case "overrideRejectedByController": self = .overrideRejectedByController
    case "activationFailed":
      self = .activationFailed(detail: try container.decode(String.self, forKey: .detail))
    case "outputDisabled": self = .outputDisabled
    case "serverStopped": self = .serverStopped
    case "persistenceFailed": self = .persistenceFailed
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .code,
        in: container,
        debugDescription: "Unknown virtual HID profile override failure: \(code)"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(code, forKey: .code)
    if case .activationFailed(let detail) = self { try container.encode(detail, forKey: .detail) }
  }
}

/// Result of `setVirtualHIDProfileOverride` and `resetVirtualHIDProfileOverride`.
public struct VirtualHIDProfileOverrideResult: Codable, Equatable, Sendable {
  /// The override the request asked for; nil for a reset or an unknown profile identifier.
  public let requested: VirtualHIDProfileID?
  /// The profile the controller publishes after the request; nil when none is live.
  public let live: VirtualHIDProfileID?
  /// How the live profile was selected: `automatic`, `override`, or `automaticAfterRejecting`.
  /// With no live profile, `override` when virtual output is disabled and the model has a stored
  /// override, else `automatic`.
  public let source: VirtualHIDProfileSource
  public let failure: VirtualHIDProfileOverrideFailure?

  public init(
    requested: VirtualHIDProfileID?,
    live: VirtualHIDProfileID?,
    source: VirtualHIDProfileSource,
    failure: VirtualHIDProfileOverrideFailure?
  ) {
    self.requested = requested
    self.live = live
    self.source = source
    self.failure = failure
  }

  public var succeeded: Bool { failure == nil }
}

/// One controller's virtual HID profile, reported in ``ApplicationServiceDeviceDescription``.
public struct ApplicationServiceVirtualHIDProfileStatus: Codable, Equatable, Sendable {
  /// The selected profile; nil before selection, when output is disabled, or when unavailable.
  public let profile: VirtualHIDProfileID?
  /// How `profile` was selected: `automatic`, `override`, or `automaticAfterRejecting`; nil
  /// when no profile is selected.
  public let source: VirtualHIDProfileSource?
  /// The stored Advanced override in effect for this controller: its unit's, else its model's;
  /// nil when it selects automatically.
  public let override: VirtualHIDProfileID?
  /// Whose override `override` is: `Unit` or `Model`; nil without an override.
  public let overrideScope: VirtualHIDProfileOverrideScope?
  /// Whether no virtual profile can represent the controller's declared controls.
  public let unavailable: Bool

  public init(
    profile: VirtualHIDProfileID?,
    source: VirtualHIDProfileSource?,
    override: VirtualHIDProfileID?,
    overrideScope: VirtualHIDProfileOverrideScope? = nil,
    unavailable: Bool
  ) {
    self.profile = profile
    self.source = source
    self.override = override
    self.overrideScope = overrideScope
    self.unavailable = unavailable
  }
}

extension VirtualHIDProfileOverrideError {
  /// The description reported as `virtualHIDProfileOverrideError` in service status.
  public var statusDescription: String {
    switch self {
    case .unreadableDirectory(let reason): "unreadable-directory: \(reason)"
    }
  }
}

/// How a controller's virtual HID profile was selected, as status and override results report it.
public enum VirtualHIDProfileSource: String, Codable, Equatable, Sendable {
  case automatic
  case override
  /// The controller could not satisfy its override, so automatic selection ran instead.
  case automaticAfterRejecting
}

/// Whose stored override is in effect for a controller: its unit's or its model's.
public enum VirtualHIDProfileOverrideScope: String, Codable, Equatable, Sendable {
  case unit = "Unit"
  case model = "Model"
}

extension VirtualHIDProfileSelector.Selection.Source {
  /// The source reported in status and override results.
  public var reported: VirtualHIDProfileSource {
    switch self {
    case .automatic: .automatic
    case .override: .override
    case .automaticAfterRejecting: .automaticAfterRejecting
    }
  }
}
