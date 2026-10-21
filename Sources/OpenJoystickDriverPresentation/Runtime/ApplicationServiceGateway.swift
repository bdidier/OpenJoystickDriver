import Combine
import Foundation
import OpenJoystickDriverKit

protocol RuntimeStatusGateway: Sendable {
  func status() async throws -> ApplicationServiceStatusPayload
  func virtualDeviceDiagnostics() async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  func frameTimings() async throws -> ApplicationServiceFrameTimingsPayload
  func requestPermissions() async throws -> PermissionManager.Snapshot
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot
  func controllerState(for selector: ControllerReference) async throws -> ControllerState?
}

protocol ControllerDiagnosticsGateway: Sendable {
  func controllerState(for selector: ControllerReference) async throws -> ControllerState?
  func packetLog(for selector: ControllerReference) async throws -> [PacketLogEntry]
}

protocol RemappingGateway: Sendable {
  func remappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload
  func remappingProfile(id: UUID) async throws -> RemappingProfile
  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func activateRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func remappingPostEventAccess() async throws -> RemappingPostEventAccessState
  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState
  func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
}

protocol VirtualOutputGateway: Sendable {
  /// `scope` is the controller's model, or the one controller by its unit ID.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID,
    for selector: ControllerReference,
    scope: VirtualHIDProfileOverrideScope
  ) async throws -> VirtualHIDProfileOverrideResult
  func resetVirtualHIDProfileOverride(
    for selector: ControllerReference,
    scope: VirtualHIDProfileOverrideScope
  ) async throws -> VirtualHIDProfileOverrideResult
  /// Returns every controller model, connected or not, to automatic virtual HID profile
  /// selection; false when the service could not apply it.
  func resetAllVirtualHIDProfileOverrides() async throws -> Bool
  func setControllerServer(
    model: ControllerModelID,
    server: ControllerServer
  ) async throws -> ControllerServerResult
  func suspendController(_ selector: ControllerReference) async throws -> ControllerSuspendResult
  func resumeController(_ selector: ControllerReference) async throws -> ControllerResumeResult
  func disconnectWirelessController(
    _ selector: ControllerReference
  ) async throws -> WirelessControllerDisconnectResult
}

extension VirtualOutputGateway {
  func setControllerServer(
    model: ControllerModelID,
    server: ControllerServer
  ) throws -> ControllerServerResult {
    ControllerServerResult(
      server: server,
      previous: .system,
      file: nil,
      created: false,
      failure: .noRecord
    )
  }

  func suspendController(_ selector: ControllerReference) throws -> ControllerSuspendResult {
    ControllerSuspendResult(state: .active, failure: .notFound)
  }

  func resumeController(_ selector: ControllerReference) throws -> ControllerResumeResult {
    ControllerResumeResult(state: .suspended, failure: .notFound)
  }

  func disconnectWirelessController(
    _ selector: ControllerReference
  ) throws -> WirelessControllerDisconnectResult {
    WirelessControllerDisconnectResult(state: .active, failure: .notFound)
  }
}

protocol ApplicationServiceGateway: RuntimeStatusGateway, ControllerDiagnosticsGateway,
  RemappingGateway, VirtualOutputGateway
{}

enum ApplicationServiceGatewayError: Error, LocalizedError, Sendable, Equatable {
  case profileRecoveryUnavailable
  case controllerSessionChangeRejected

  var errorDescription: String? {
    switch self {
    case .profileRecoveryUnavailable:
      return OJDLocalized.string("profiles.unavailable")
    case .controllerSessionChangeRejected:
      return OJDLocalized.string(
        "error.controllerSessionChangeRejected"
      )
    }
  }
}

package actor ApplicationServiceClientGateway: ApplicationServiceGateway {
  let client: ApplicationServiceClient
  var connectionTask: Task<Void, Never>?

  package init(client: ApplicationServiceClient = ApplicationServiceClient()) {
    self.client = client
  }
}

extension RemappingGateway {
  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await Task.yield()
    throw ApplicationServiceGatewayError.profileRecoveryUnavailable
  }

  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await Task.yield()
    throw ApplicationServiceGatewayError.profileRecoveryUnavailable
  }
}

extension ApplicationServiceClientGateway: InputTestDeviceGateway {
  func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for selector: ControllerReference
  ) async throws -> ControllerOutputResult {
    await ensureConnection()
    return try await client.sendControllerOutput(
      command,
      for: selector
    )
  }

  func previewColor(
    for selector: ControllerReference,
    token: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    await ensureConnection()
    return try await client.previewPhysicalColor(
      for: selector,
      token: token,
      red: red,
      green: green,
      blue: blue
    )
  }

  func releaseColorPreview(for selector: ControllerReference, token: UUID) async throws -> Bool {
    await ensureConnection()
    return try await client.releasePhysicalColorPreview(
      for: selector,
      token: token
    )
  }

  func motionCalibration(
    for selector: ControllerReference,
    command: RemappingMotionCalibrationCommand?
  ) async throws -> RemappingMotionCalibrationStatus {
    await ensureConnection()
    return try await client.remappingMotionCalibration(for: selector, command: command)
  }
}
