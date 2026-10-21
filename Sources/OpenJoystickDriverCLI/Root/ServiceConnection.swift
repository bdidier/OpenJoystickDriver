import Foundation
import OpenJoystickDriverKit

/// The CLI's only route to the OpenJoystickDriver service.
///
/// No command starts the service implicitly: a request to a stopped service fails with exit
/// code 69, and `ojd service start` is the one command that launches it.
enum ServiceConnection {
  /// The service socket; tests point it at a private server.
  @TaskLocal
  static var socketPath = LocalServiceRPCTransport.defaultSocketPath

  /// The service's process identifier, or nil when nothing answers on the socket.
  static func processIdentifier() -> Int32? {
    LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath)
  }

  /// Connects to a running service and runs `body` within the `--timeout` request deadline.
  static func request<T: Sendable>(
    timeout: Double = CLIContext.current.requestTimeout,
    _ body: @escaping @Sendable (ApplicationServiceClient) async throws -> T
  ) async throws -> T {
    let client = try await open()
    defer { client.disconnect() }
    return try await withDeadline(seconds: timeout) { try await body(client) }
  }

  /// Connects to a running service for a command that sends many requests, such as a stream.
  ///
  /// The caller disconnects the client and bounds each request with `withDeadline`.
  ///
  /// `client` is the connection to try; tests pass one whose probes they count.
  static func open(
    client: ApplicationServiceClient = ApplicationServiceClient(socketPath: socketPath)
  ) async throws -> ApplicationServiceClient {
    await client.connect(timeoutSeconds: 0)
    guard client.isConnected else { throw CLIFailure.serviceUnavailable }
    return client
  }

  /// Runs `operation` until it finishes or `seconds` elapse.
  ///
  /// Kit client errors become `CLIFailure` values; a missed deadline names `--timeout`.
  static func withDeadline<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    do { return try await withTimeout(seconds: seconds, operation) } catch let error as TimeoutError
    {
      throw CLIFailure.timedOut(seconds: error.seconds)
    } catch {
      throw failure(for: error)
    }
  }

  static func failure(for error: any Error) -> any Error {
    switch error {
    case ApplicationServiceClientError.notConnected: CLIFailure.serviceUnavailable
    case ApplicationServiceClientError.timeout: CLIFailure.timedOut(seconds: nil)
    case LocalServiceRPCError.peerRejected: CLIFailure.peerRejected
    case is CLIFailure, is CancellationError: error
    case let rejection as ApplicationServiceRemappingRPCError
    where rejection.code == .duplicateName:
      CLIFailure(
        rejection.code.errorCode,
        CLILocalized.text(
          "cli.error.duplicate_profile_name"
        )
      )
    case let rejection as ApplicationServiceRemappingRPCError
    where rejection.code == .packageProfileReadOnly:
      CLIFailure(
        rejection.code.errorCode,
        CLILocalized.text(
          "error.E3029"
        )
      )
    case let rejection as ApplicationServiceRemappingRPCError:
      CLIFailure.serviceRequestFailed(rejection.localizedDescription, id: rejection.code.errorCode)
    default: CLIFailure.serviceRequestFailed(error.localizedDescription)
    }
  }
}

extension CLIFailure {
  static func timedOut(seconds: Double?) -> Self {
    guard let seconds else {
      return Self(
        .serviceTimeout,
        CLILocalized.text(
          "cli.error.service_timeout"
        )
      )
    }
    return Self(
      .serviceTimeout,
      CLILocalized.format(
        "cli.error.request_timeout",
        seconds.durationText
      )
    )
  }

  static var peerRejected: Self {
    Self(
      .peerRejected,
      CLILocalized.text(
        "cli.error.peer_rejected"
      )
    )
  }
}

extension Double {
  /// Seconds as a localized value with a unit symbol, such as `0.5s` or `5 с`. A symbol needs
  /// no plural agreement, so messages read correctly for any value.
  var durationText: String { durationText(locale: .current) }

  func durationText(locale: Locale) -> String {
    Measurement(value: self, unit: UnitDuration.seconds)
      .formatted(.measurement(width: .narrow, numberFormatStyle: .number).locale(locale))
  }
}
