import Foundation
import OpenJoystickDriverKit

/// The `ojd diagnose --json` result. `output` is absent unless `--output` wrote a file. `timings`
/// holds the newest per-stage frame timestamps of each connected controller; it is empty when the
/// service is stopped or has no frames.
struct DiagnoseReport: Encodable, Equatable {
  let checks: [DiagnoseCheck]
  let timings: [ControllerFrameTimings]
  let output: String?

  var failureCount: Int { checks.filter { $0.status == .fail }.count }

  /// One `id`, `status`, `detail` row per check, then one `timing`, controller, sequence, stage,
  /// nanoseconds row per recorded stage.
  var plainRows: [[String]] {
    checks.map { [$0.id, CommandLineName.kebab($0.status.rawValue), $0.detail] }
      + timings.flatMap { controller in
        controller.frames.flatMap { frame in
          frame.stages.map {
            [
              "timing", controller.controller, String(frame.sequence),
              CommandLineName.kebab($0.stage.rawValue),
              String($0.nanoseconds),
            ]
          }
        }
      }
  }
}
