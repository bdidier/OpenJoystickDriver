import Foundation

/// Receiver-backed controllers can report logical controller connect/disconnect
/// independently from the HID device that carries reports.
public enum ControllerInputConnectionState: Sendable, Equatable {
  case connected
  case disconnected
}

public enum ControllerInputHealthState: String, Codable, Sendable {
  case healthy = "Healthy"
  case stale = "Stale"
  case waitingForNeutral = "WaitingForNeutral"
}

public enum ControllerInputHealthFailureReason: String, Codable, CaseIterable, Sendable {
  case missingReports = "MissingReports"
  case freshnessNotAdvancing = "FreshnessNotAdvancing"
  /// No input since the session started from a controller that sends none until its home button
  /// is pressed (``InputStartAction/pressGuide``).
  case guideNotPressed = "GuideNotPressed"
}

/// What the user does before a controller sends its first input report; the family's protocol
/// description names it (`inputStart`).
public enum InputStartAction: String, Sendable {
  /// Press the home button: the PS button of a USB DualShock 3.
  case pressGuide = "PressGuide"
}

public struct ControllerInputHealth: Codable, Sendable {
  public let state: ControllerInputHealthState
  public let reportFormat: String?
  public let lastReportAgeNanoseconds: UInt64?
  public let failureReason: ControllerInputHealthFailureReason?
  public let recoveryCount: Int

  public init(
    state: ControllerInputHealthState,
    reportFormat: String? = nil,
    lastReportAgeNanoseconds: UInt64? = nil,
    failureReason: ControllerInputHealthFailureReason? = nil,
    recoveryCount: Int = 0
  ) {
    self.state = state
    self.reportFormat = reportFormat
    self.lastReportAgeNanoseconds = lastReportAgeNanoseconds
    self.failureReason = failureReason
    self.recoveryCount = recoveryCount
  }
}
