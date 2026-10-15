import Foundation
import OpenJoystickDriverKit

/// The `ojd diagnose --json` result. `bundle` is absent unless `--bundle` wrote a file. `timings`
/// holds the newest per-stage frame timestamps of each connected controller; it is empty when the
/// service is stopped or has no frames.
struct DiagnoseReport: Encodable, Equatable {
  let checks: [DiagnoseCheck]
  let timings: [ControllerFrameTimings]
  let bundle: String?

  var failureCount: Int { checks.filter { $0.status == .fail }.count }

  var plainRows: [[String]] { checks.map { [$0.id, $0.status.rawValue, $0.detail] } }
}
