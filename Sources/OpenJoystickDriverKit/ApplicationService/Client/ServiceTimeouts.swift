import Foundation

/// Seconds the CLI waits on the service, and the service's own Bluetooth wait they depend on.
public enum ServiceTimeouts {
  /// One service request.
  public static let request: Double = 0.5
  /// A command that waits for the service to start, stop, or settle.
  public static let wait: Double = 5
  /// A permission request, since the service waits for macOS to register it.
  public static let permissionRequest: Double = 10
  /// A test notification request, which the service holds until the app reports or the pickup and
  /// answer deadlines pass, plus the time for its reply.
  public static let testNotification: Double =
    TestNotificationDeadlines.pickupSeconds + TestNotificationDeadlines.answerSeconds
    + applicationServiceDefaultReplyTimeoutSeconds
  /// How long the service waits for a Bluetooth controller to disconnect.
  public static let bluetoothDisconnect: Double = 3
  /// A disconnect request, which leaves room for the service's Bluetooth wait and its reply.
  public static let bluetoothDisconnectRequest: Double = bluetoothDisconnect * 2
}
