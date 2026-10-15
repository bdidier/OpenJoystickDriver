import Combine
import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceClientGateway {

  func status() async throws -> ApplicationServiceStatusPayload {
    await ensureConnection()
    return try await client.getStatus()
  }

  func virtualDeviceDiagnostics() async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    await ensureConnection()
    return try await client.getVirtualDeviceDiagnostics()
  }

  func requestPermissions() async throws -> PermissionManager.Snapshot {
    await ensureConnection()
    return try await client.requestRequiredAccess()
  }

  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot {
    await ensureConnection()
    return try await client.requestAccess(requirement)
  }

  func controllerState(for selector: ControllerReference) async throws -> ControllerState? {
    await ensureConnection()
    return try await client.controllerState(for: selector)
  }

  func packetLog(for selector: ControllerReference) async throws -> [PacketLogEntry] {
    await ensureConnection()
    return try await client.packetLog(for: selector)
  }

  func remappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.getRemappingSnapshot()
  }

  func remappingProfile(id: UUID) async throws -> RemappingProfile {
    await ensureConnection()
    return try await client.getRemappingProfile(id: id)
  }

  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.createRemappingProfile(profile)
  }

  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
  }

  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.importRemappingProfile(profile)
  }

  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deleteRemappingProfile(id: id)
  }

  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deleteDamagedRemappingProfile(issueID: issueID)
  }

  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.resetRemappingProfileLibrary(issueID: issueID)
  }

  func activateRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  {
    await ensureConnection()
    return try await client.activateRemappingProfile(id: id, allowEmpty: true)
  }

  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
  }

  func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deactivateRemappingProfile(profileID: profileID)
  }

  func remappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    await ensureConnection()
    return try await client.getRemappingPostEventAccess()
  }

  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    await ensureConnection()
    return try await client.requestRemappingPostEventAccess()
  }

  func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.pairRemappingJoyCons(left: left, right: right, profileID: profileID)
  }

  func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.unpairRemappingJoyCons(sessionID: sessionID)
  }

  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID,
    for selector: ControllerReference
  ) async throws -> VirtualHIDProfileOverrideResult {
    await ensureConnection()
    return try await client.setVirtualHIDProfileOverride(
      profile.rawValue,
      for: selector
    )
  }

  func resetVirtualHIDProfileOverride(
    for selector: ControllerReference
  ) async throws -> VirtualHIDProfileOverrideResult {
    await ensureConnection()
    return try await client.resetVirtualHIDProfileOverride(for: selector)
  }

  func setControllerOwnership(
    model: ControllerModelID,
    ownership: ControllerServer
  ) async throws -> ControllerOwnershipResult {
    await ensureConnection()
    return try await client.setControllerOwnership(model: model, ownership: ownership)
  }

  func suspendController(_ selector: ControllerReference) async throws -> ControllerSuspendResult {
    await ensureConnection()
    return try await client.suspendController(selector)
  }

  func resumeController(_ selector: ControllerReference) async throws -> ControllerResumeResult {
    await ensureConnection()
    return try await client.resumeController(selector)
  }

  func disconnectWirelessController(
    _ selector: ControllerReference
  ) async throws -> WirelessControllerDisconnectResult {
    await ensureConnection()
    return try await client.disconnectWirelessController(selector)
  }

  func ensureConnection() async {
    guard !client.isConnected else { return }
    if let connectionTask {
      await connectionTask.value
      return
    }
    let client = self.client
    let task = Task { await client.connect() }
    connectionTask = task
    await task.value
    connectionTask = nil
  }
}
