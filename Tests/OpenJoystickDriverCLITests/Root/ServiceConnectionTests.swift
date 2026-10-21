import Foundation
import Testing

@testable import OpenJoystickDriverCLI

struct ServiceConnectionTests {
  /// With nothing listening on the socket, `open()` reports the service as stopped after its one
  /// probe, whose socket timeout is 0.2 s; the rest of the bound is scheduling margin.
  @Test
  func aStoppedServiceIsUnavailableAfterOneProbe() async {
    let start = Date()
    await #expect(throws: CLIFailure.serviceUnavailable) {
      try await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
        _ = try await ServiceConnection.open()
      }
    }
    #expect(Date().timeIntervalSince(start) < 0.2 + 2)
  }
}
