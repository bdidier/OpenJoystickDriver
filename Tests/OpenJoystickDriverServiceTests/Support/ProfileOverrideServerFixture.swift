import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// A server whose automatic dispatcher builds retarget probes and reads isolated overrides.
struct ProfileOverrideServerFixture {
  let server: ApplicationServiceServer
  let personaDirectory: URL
  let log: RetargetEventLog

  var store: VirtualHIDProfileOverrideStore {
    VirtualHIDProfileOverrideStore(directory: personaDirectory)
  }

  func change(
    _ change: ApplicationServiceServer.VirtualHIDProfileOverrideChange,
    controller: ControllerReference = .model(ControllerModelID(vendorID: 1, productID: 2)),
    unit: Bool = false
  ) async -> VirtualHIDProfileOverrideResult {
    await server.changeVirtualHIDProfileOverride(change, for: controller, unit: unit)
  }

  func tearDown() async {
    await server.automaticUserSpaceDispatcher()?.close()
    try? FileManager.default.removeItem(at: personaDirectory)
  }
}

extension VirtualHIDProfileOverrideStore {
  func setSdlCompatibleForTest() { try? set(.sdlCompatible, vendorID: 1, productID: 2) }
}
