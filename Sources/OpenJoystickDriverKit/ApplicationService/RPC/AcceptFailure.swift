import Darwin
import Foundation

/// What an accept loop does after `accept` fails; the RPC server and the endpoint server share it.
package enum AcceptFailure: Equatable, Sendable {
  /// The connection was dropped or the call interrupted, or none was waiting; accept again at
  /// once.
  case retry
  /// The process or system is out of descriptors or memory. Connections wait in the queue; the
  /// loop reports the reason, waits and accepts again.
  case waitForResources
  /// The listening socket is unusable, so the loop ends.
  case fatal

  /// Milliseconds an accept loop waits after `waitForResources`.
  package static let resourceWaitMilliseconds: Int32 = 500

  package init(errno code: Int32) {
    switch code {
    case EINTR, ECONNABORTED, EAGAIN: self = .retry
    case EMFILE, ENFILE, ENOBUFS, ENOMEM: self = .waitForResources
    default: self = .fatal
    }
  }

  /// The line that reports a failure of `server`'s accept loop. A fatal one carries `ended`, the
  /// code that explains to the user what stopped.
  package static func message(
    server: String,
    errno code: Int32,
    action: Self,
    waitMilliseconds: Int32 = resourceWaitMilliseconds,
    ended: ErrorCode? = nil
  ) -> String {
    let reason = String(cString: strerror(code))
    switch action {
    case .waitForResources:
      return "[\(server)] Cannot accept connections (\(reason), errno \(code)); "
        + "retrying in \(waitMilliseconds) ms"
    case .retry, .fatal:
      let explanation = ended.map { "\($0.rawValue): \($0.localizedExplanation) " } ?? ""
      return "[\(server)] \(explanation)Stopped accepting connections (\(reason), errno \(code))"
    }
  }

  /// Applies the failure `code` of `server`'s accept loop and returns whether the loop goes on.
  /// A wait for resources ends early, and the loop ends, when `wake` becomes readable or hangs up.
  package static func continuesAfter(
    errno code: Int32,
    server: String,
    wake: Int32,
    waitMilliseconds: Int32 = resourceWaitMilliseconds,
    ended: ErrorCode? = nil,
    report: (String) -> Void
  ) -> Bool {
    let action = Self(errno: code)
    switch action {
    case .retry: return true
    case .waitForResources:
      report(
        message(server: server, errno: code, action: action, waitMilliseconds: waitMilliseconds)
      )
      return !wait(milliseconds: waitMilliseconds, wake: wake)
    case .fatal:
      report(message(server: server, errno: code, action: action, ended: ended))
      return false
    }
  }

  /// Waits up to `milliseconds`; true when `wake` became readable or hung up first.
  package static func wait(milliseconds: Int32, wake: Int32) -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(milliseconds) * 1_000_000
    while true {
      let now = DispatchTime.now().uptimeNanoseconds
      guard now < deadline else { return false }
      let remaining = Int32(min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max)))
      var polled = [pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
      let ready = poll(&polled, 1, remaining)
      if ready < 0 {
        if errno == EINTR { continue }
        return true
      }
      if polled[0].revents != 0 { return true }
    }
  }
}
