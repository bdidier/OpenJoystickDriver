import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ServiceConnectionTests {
  private func server(at socketPath: String) -> LocalServiceRPCServer {
    LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _, completion in completion(LocalServiceRPCResponse(result: nil, error: "none")) }
    )
  }

  /// A service that starts accepting a moment after the command probes is still found, because
  /// `open()` keeps probing for `connectWaitSeconds`.
  @Test
  func aServiceThatAcceptsLateIsStillFound() async throws {
    let socketPath = temporarySocketPath()
    let late = server(at: socketPath)
    defer { late.stop() }
    let starting = Task {
      try await Task.sleep(nanoseconds: 250_000_000)
      try late.start()
    }
    let client = try await ServiceConnection.$connectWaitSeconds.withValue(20) {
      try await ServiceConnection.$socketPath.withValue(socketPath) {
        try await ServiceConnection.open()
      }
    }
    defer { client.disconnect() }
    try await starting.value
    #expect(client.isConnected)
  }

  /// A stopped service costs a command the connect wait and no unbounded time.
  @Test
  func aStoppedServiceIsReportedWithinTheConnectWait() async {
    let start = Date()
    await #expect(throws: CLIFailure.self) {
      try await ServiceConnection.$connectWaitSeconds.withValue(0.3) {
        try await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
          _ = try await ServiceConnection.open()
        }
      }
    }
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed >= 0.3)
    #expect(elapsed < 10)
  }
}
