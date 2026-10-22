#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct MotionCalibrationControls: View {
    @ObservedObject
    var model: MotionCalibrationViewModel
    @State
    private var attempt = 0

    private struct LoadID: Equatable {
      let selector: ControllerReference?
      let attempt: Int
    }

    /// Loads the calibration status of the selected controller, and keeps it current while the
    /// service can still change it. A new selection or a retry starts the load again.
    var body: some View {
      content.task(id: LoadID(selector: model.selector, attempt: attempt)) {
        await model.refreshWhileCalibrating()
      }
    }

    private var content: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(
          OJDLocalized.string(
            "ui.motion.calibration.instructions"
          )
        ).font(.caption).fixedSize(horizontal: false, vertical: true)
        if let status = model.status {
          if !status.hasMotionBaseline {
            Text(
              OJDLocalized.string(
                "ui.motion.calibration.waiting"
              )
            ).font(.caption).fixedSize(horizontal: false, vertical: true)
          }
          Text(
            status.isCollecting
              ? OJDLocalized.string("ui.motion.calibration.collecting")
              : OJDLocalized.string(
                "ui.motion.calibration.paused"
              )
          )
          Text(
            OJDLocalized.formatted(
              "ui.motion.calibration.offset",
              status.offsetDegreesPerSecond.x,
              status.offsetDegreesPerSecond.y,
              status.offsetDegreesPerSecond.z
            )
          ).font(.caption).fixedSize(horizontal: false, vertical: true)
          if status.isCollecting {
            Text(
              OJDLocalized.string(
                "ui.motion.calibration.continues"
              )
            ).font(.caption).fixedSize(horizontal: false, vertical: true)
          }
        }
        if let error = model.errorMessage {
          Text(error).font(.caption).foregroundColor(.red).fixedSize(
            horizontal: false,
            vertical: true
          )
          Button(OJDLocalized.string("action.tryAgain")) { attempt += 1 }
        }
        HStack {
          Button(OJDLocalized.string("ui.motion.calibration.start")) {
            Task { await model.perform(.start) }
          }.disabled(model.status?.hasMotionBaseline != true || model.status?.isCollecting == true)
          Button(OJDLocalized.string("ui.motion.calibration.pause")) {
            Task { await model.perform(.pause) }
          }.disabled(model.status?.isCollecting != true)
          Button(OJDLocalized.string("action.reset")) {
            Task { await model.perform(.reset) }
          }.disabled(model.status == nil)
          if model.isBusy { ProgressView().controlSize(.small) }
        }
      }.disabled(model.selector == nil || model.isBusy)
    }
  }
#endif
