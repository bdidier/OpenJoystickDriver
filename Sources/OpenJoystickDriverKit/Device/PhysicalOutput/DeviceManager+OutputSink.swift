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

  public func consume(
    _ release: MappingOutputRelease,
    for controller: LogicalControllerID
  ) async throws {
    guard await releaseMappingPhysicalOutputs(for: controller) else {
      throw StreamBoundaryError.rejected(.physicalOutput, "mapping outputs not released")
    }
  }

  public func consume(_ color: ProfileColorClaim, for controller: LogicalControllerID) async throws
  {
    guard await setProfilePhysicalColor(color.color, for: controller) else {
      throw StreamBoundaryError.rejected(.physicalOutput, "profile colour not applied")
    }
  }
}
