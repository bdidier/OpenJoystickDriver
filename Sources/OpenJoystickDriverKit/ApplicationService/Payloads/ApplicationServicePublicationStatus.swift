/// Whether a virtual device publishes one controller, reported in
/// ``ApplicationServiceDeviceDescription``.
public struct ApplicationServicePublicationStatus: Codable, Equatable, Sendable {
  /// The publication state of a controller.
  public enum State: String, Codable, Equatable, Sendable {
    /// A virtual device is installed for the controller.
    case published = "Published"
    /// No virtual device is installed; `reason` says why.
    case notPublished = "NotPublished"
    /// The last send to the virtual device failed; `failure` carries the text.
    case failed = "Failed"
  }

  /// Why a controller is not published.
  public enum NotPublishedReason: String, Codable, CaseIterable, Equatable, Sendable {
    /// Virtual output is off.
    case outputDisabled = "OutputDisabled"
    /// The system serves the controller as a gamepad.
    case systemGamepad = "SystemGamepad"
    /// The controller's native HID reports reach applications unchanged.
    case nativeHIDPassThrough = "NativeHIDPassThrough"
    /// Another virtual device already stands for the controller.
    case upstreamVirtualDevice = "UpstreamVirtualDevice"
    /// The user session of the controller is suspended.
    case sessionSuspended = "SessionSuspended"
    /// No persona can represent the controller's primary controls.
    case noVirtualProfile = "NoVirtualProfile"
    /// Remapping suppresses the virtual device.
    case suppressed = "Suppressed"
    /// The controller has sent no input yet.
    case noInputYet = "NoInputYet"
  }

  public let state: State
  /// Why the controller is not published; set exactly when `state` is `NotPublished`.
  public let reason: NotPublishedReason?
  /// The text of the failed send; set exactly when `state` is `Failed`.
  public let failure: String?
  /// The virtual HID profile the controller publishes or tries to publish.
  public let target: VirtualHIDProfileID?
  /// System uptime in nanoseconds of the last send to the virtual device.
  public let lastAttemptedNanoseconds: UInt64?
  /// System uptime in nanoseconds of the last send the virtual device accepted.
  public let lastCompletedNanoseconds: UInt64?

  public init(
    state: State,
    reason: NotPublishedReason? = nil,
    failure: String? = nil,
    target: VirtualHIDProfileID? = nil,
    lastAttemptedNanoseconds: UInt64? = nil,
    lastCompletedNanoseconds: UInt64? = nil
  ) {
    self.state = state
    self.reason = reason
    self.failure = failure
    self.target = target
    self.lastAttemptedNanoseconds = lastAttemptedNanoseconds
    self.lastCompletedNanoseconds = lastCompletedNanoseconds
  }
}
