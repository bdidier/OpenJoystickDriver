import Foundation

public enum WirelessControllerDisconnectOutcome: Sendable, Equatable {
  case disconnected
  /// The host rejected the disconnect with a status code of its Bluetooth stack.
  case failed(Int32)
  case stillConnected
  case timedOut
}

public protocol WirelessControllerDisconnecting: Sendable {
  func disconnect(
    address: String,
    timeoutNanoseconds: UInt64
  ) async -> WirelessControllerDisconnectOutcome
}
