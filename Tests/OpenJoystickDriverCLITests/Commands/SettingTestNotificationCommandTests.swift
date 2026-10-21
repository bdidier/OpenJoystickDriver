import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct SettingTestNotificationCommandTests {
  /// A service that answers `sendTestNotification` with `outcome` after `answerDelay` and records
  /// its methods.
  private func serve(
    outcome: TestNotificationOutcome,
    socketPath: String,
    received: Locked<[String]> = Locked([]),
    answerDelay: Duration = .zero
  ) throws -> LocalServiceRPCServer {
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        received.withLock { $0.append(request.method) }
        guard request.method == ApplicationServiceRPCMethod.sendTestNotification.rawValue else {
          return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
        }
        try? await Task.sleep(for: answerDelay)
        return LocalServiceRPCResponse(result: try? JSONEncoder().encode(outcome), error: nil)
      }
    )
    try server.start()
    return server
  }

  /// Runs the command with `--timeout 5` unless `timeout` is nil, which leaves the default.
  private func run(
    _ arguments: [String],
    socketPath: String,
    timeout: String? = "5"
  ) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await CLIRun.run(
        ["setting", "test-notification"] + arguments + (timeout.map { ["--timeout", $0] } ?? [])
      )
    }
  }

  @Test
  func withoutTimeoutTheCommandWaitsForAnAnswerSlowerThanTheRequestDeadline() async throws {
    let socketPath = temporarySocketPath()
    let delay = Duration.milliseconds(800)
    #expect(delay > .seconds(ServiceTimeouts.request))
    let server = try serve(outcome: .shown, socketPath: socketPath, answerDelay: delay)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath, timeout: nil)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      result.standardError.contains(CLILocalized.text("cli.setting.testNotification.success"))
    )
  }

  @Test
  func aShownNotificationSucceedsInEachFormat() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(outcome: .shown, socketPath: socketPath, received: received)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath)
    let plain = await run(["--plain"], socketPath: socketPath)
    let json = await run(["--json"], socketPath: socketPath)

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.isEmpty)
    #expect(human.standardError.contains(CLILocalized.text("cli.setting.testNotification.success")))
    #expect(plain.standardOutput == "shown\n")
    #expect(try json.details()["outcome"] as? String == "Shown")
    #expect(
      received.withLock {
        $0 == Array(repeating: ApplicationServiceRPCMethod.sendTestNotification.rawValue, count: 3)
      }
    )
  }

  @Test
  func noAnswerFailsWithE2037() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(outcome: .noAnswer, socketPath: socketPath)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath)
    let json = await run(["--json"], socketPath: socketPath)

    #expect(human.code == 69)
    #expect(
      human.standardError
        == CLIFailure(.noApplicationAnswered, CLILocalized.text("error.E2037")).line + "\n"
    )
    #expect(human.standardOutput.isEmpty)
    #expect(json.code == 69)
    #expect(json.standardOutput.isEmpty)
  }

  @Test
  func deniedNotificationsFailWithE2038AndExit77() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(outcome: .denied, socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(result.code == 77)
    #expect(
      result.standardError
        == CLIFailure(.notificationsDenied, CLILocalized.text("error.E2038")).line + "\n"
    )
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func aFailedDeliveryNamesTheSystemsReason() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(outcome: .failed("the system refused"), socketPath: socketPath)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath)

    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2006]: "))
    #expect(result.standardError.contains("the system refused"))
  }

  @Test
  func aStoppedServiceFailsWithE2004() async {
    let result = await run([], socketPath: temporarySocketPath())

    #expect(result.code == 69)
    #expect(result.standardError == CLIFailure.serviceUnavailable.line + "\n")
  }
}
