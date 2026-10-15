import Foundation
import OpenJoystickDriverKit

/// Reads controllers from the service in-process, for the endpoint's stream.
///
/// Holds the server weakly, because the server owns the endpoint that owns this source.
struct ApplicationServiceWatchSource: ControllerWatchSource {
  weak var server: ApplicationServiceServer?

  func devices() async throws -> [ApplicationServiceDeviceDescription] {
    guard let server else { return [] }
    return server.describingVirtualHIDProfiles(
      await server.deviceManager.connectedDeviceDescriptions().map {
        ($0.logicalControllerID, ApplicationServiceDeviceDescription(snapshot: $0))
      }
    )
  }

  func state(of device: ApplicationServiceDeviceDescription) async throws -> ControllerState? {
    await server?.deviceManager.controllerState(for: .session(device.sessionToken))
  }

  func output(
    of device: ApplicationServiceDeviceDescription
  ) async throws
    -> ApplicationServiceVirtualOutputState?
  {
    guard let server,
      let identifier = await server.deviceManager.connectedIdentifier(
        for: .session(device.sessionToken)
      ),
      let state = await server.automaticUserSpaceDispatcher()?.virtualOutputState(for: identifier)
    else { return nil }
    return ApplicationServiceVirtualOutputState(state)
  }
}
