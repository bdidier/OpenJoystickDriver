import Foundation
import OpenJoystickDriverKit

/// Starts the application service the way `ojd service start` does: when nothing answers on the
/// service socket, opens the app bundle in the background and waits until the socket answers.
struct ServiceStarter {
  enum Failure: Error, Equatable {
    /// The running copy is not inside an app bundle, so there is nothing to open.
    case noBundle
    /// macOS could not open the bundle at this path.
    case openFailed(String)
    /// The bundle opened but the service did not answer in time.
    case notReady

    var message: String {
      switch self {
      case .noBundle: return OJDLocalized.string("banner.service.noBundle")
      case .openFailed(let path):
        return OJDLocalized.formatted("cli.service.start.open_failed", path)
      case .notReady: return OJDLocalized.string("banner.service.notReady")
      }
    }
  }

  var processIdentifier: @Sendable () -> Int32? = {
    LocalServiceRPCClient.serverProcessIdentifier()
  }
  var bundleURL: @Sendable () -> URL? = {
    BuildIdentity.applicationBundleURL(executableURL: Bundle.main.executableURL)
  }
  var open: @Sendable (URL) throws -> Bool = { try BuildIdentity.openInBackground($0) }
  /// Seconds to wait for the service to answer after the bundle opened.
  var timeout: Double = ServiceTimeouts.wait
  var pollNanoseconds: UInt64 = 100_000_000

  func start() async throws {
    guard processIdentifier() == nil else { return }
    guard let bundle = bundleURL() else { throw Failure.noBundle }
    guard try open(bundle) else { throw Failure.openFailed(bundle.path) }
    let deadline = Date().addingTimeInterval(timeout)
    while processIdentifier() == nil {
      guard Date() < deadline else { throw Failure.notReady }
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }
  }
}
