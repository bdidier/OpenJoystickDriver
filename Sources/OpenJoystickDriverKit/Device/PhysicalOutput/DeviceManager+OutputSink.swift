import Foundation

/// The physical-output path: the manager takes output commands for a connected controller.
extension DeviceManager: OutputSink {
  nonisolated public var destination: OutputDestination { .physicalOutput }

  public func consume(
    _ command: ControllerOutputCommand,
    for controller: LogicalControllerID
  )
    async throws
  {
    let result = await sendControllerOutput(command, toConnected: controller)
    guard result.outcome == .delivered else {
      throw StreamBoundaryError.rejected(.physicalOutput, result.outcome.rawValue)
    }
  }

  public func consume(_ claim: MappingOutputClaim, for controller: LogicalControllerID) async throws
  {
    let applied = await setMappingPhysicalOutput(
      claim.output,
      active: claim.active,
      owner: claim.owner,
      for: controller
    )
    guard applied else {
      throw StreamBoundaryError.rejected(.physicalOutput, "mapping output not applied")
    }
  }
}
