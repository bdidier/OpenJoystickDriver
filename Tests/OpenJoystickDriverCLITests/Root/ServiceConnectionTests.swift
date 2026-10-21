import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.removingTemporarySockets)
struct ServiceConnectionTests {
  /// With nothing listening on the socket, `open()` reports the service as stopped after one
  /// probe: it adds no wait and no retry.
  @Test
  func aStoppedServiceIsUnavailableAfterOneProbe() async {
    let client = ApplicationServiceClient(socketPath: temporarySocketPath())

    await #expect(throws: CLIFailure.serviceUnavailable) {
      _ = try await ServiceConnection.open(client: client)
    }

    #expect(client.unansweredProbeCount == 1)
  }
}
