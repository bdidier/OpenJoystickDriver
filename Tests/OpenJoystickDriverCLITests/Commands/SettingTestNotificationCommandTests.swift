import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct SettingTestNotificationCommandTests {
  /// A service that answers `sendTestNotification` with `announcedApps` and records its methods.
  private func serve(
    announcedApps: Int,
    socketPath: String,
    received: Locked<[String]> = Locked([])
  ) throws -> LocalServiceRPCServer {
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        received.withLock { $0.append(request.method) }
        guard request.method == ApplicationServiceRPCMethod.sendTestNotification.rawValue else {
          completion(LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)"))
          return
        }
        completion(
          LocalServiceRPCResponse(
            result: try? JSONEncoder().encode(
              TestNotificationAnnouncement(announcedApps: announcedApps)
            ),
            error: nil
          )
        )
      }
    )
    try server.start()
    return server
  }

  private func run(_ arguments: [String], socketPath: String) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await CLIRun.run(["setting", "test-notification"] + arguments + ["--timeout", "5"])
    }
  }

  @Test
  func anAnnouncementToAWaitingAppSucceedsInEachFormat() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(announcedApps: 1, socketPath: socketPath, received: received)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath)
    let plain = await run(["--plain"], socketPath: socketPath)
    let json = await run(["--json"], socketPath: socketPath)

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.isEmpty)
    #expect(human.standardError.contains(CLILocalized.text("cli.setting.testNotification.success")))
    #expect(plain.standardOutput == "1\n")
    #expect(try json.details()["announcedApps"] as? Int == 1)
    #expect(
      received.withLock {
        $0 == Array(repeating: ApplicationServiceRPCMethod.sendTestNotification.rawValue, count: 3)
      }
    )
  }

  @Test
  func noWaitingAppFailsWithE2037() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(announcedApps: 0, socketPath: socketPath)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath)
    let json = await run(["--json"], socketPath: socketPath)

    #expect(human.code == 69)
    #expect(
      human.standardError
        == CLIFailure(.noApplicationListening, CLILocalized.text("error.E2037")).line + "\n"
    )
    #expect(human.standardError.hasPrefix("error[E2037]: "))
    #expect(human.standardOutput.isEmpty)
    #expect(json.code == 69)
    #expect(json.standardOutput.isEmpty)
  }

  @Test
  func aStoppedServiceFailsWithE2004() async {
    let result = await run([], socketPath: temporarySocketPath())

    #expect(result.code == 69)
    #expect(result.standardError == CLIFailure.serviceUnavailable.line + "\n")
  }
}
