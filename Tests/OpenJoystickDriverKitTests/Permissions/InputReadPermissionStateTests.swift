import Foundation
import OpenJoystickDriverKit
import Testing

struct InputReadPermissionStateTests {
  @Test
  func accessStateNormalizesMultilineProbeOutput() {
    #expect(PermissionManager.AccessState(status: "granted") == .granted)
    #expect(
      PermissionManager.AccessState(
        status: "[Application service] Starting permission-check probe mode\nDENIED\n"
      ) == .denied
    )
    #expect(PermissionManager.AccessState(status: "unexpected") == .unknown)
  }

  @Test
  func permissionSnapshotRequiresBothStates() {
    #expect(PermissionManager.Snapshot(inputRead: .granted, inputInject: .granted).isReady)
    #expect(!PermissionManager.Snapshot(inputRead: .granted, inputInject: .denied).isReady)
  }

  @Test
  func accessStateHasStableTransportAndDisplayValues() throws {
    let encoded = try JSONEncoder().encode(PermissionManager.AccessState.denied)
    let decoded = try JSONDecoder().decode(PermissionManager.AccessState.self, from: encoded)

    #expect(decoded == .denied)
  }
}
