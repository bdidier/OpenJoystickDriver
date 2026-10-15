import Foundation

/// The physical-output path: the manager takes output commands for a connected controller.
extension DeviceManager: OutputSink {
  public nonisolated var destination: OutputDestination { .physicalOutput }

  public func consume(_ command: ControllerOutputCommand, for controller: LogicalControllerID)
    async throws
  {
    let result = await sendControllerOutput(command, toConnected: controller)
    guard result.outcome == .delivered else {
      throw StreamBoundaryError.rejected(.physicalOutput, result.outcome.rawValue)
    }
  }
}
