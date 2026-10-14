import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// An ownership toggle keeps the user's suspension of a controller that the HID backend admits
/// again; a physical disconnect still ends it. The GameSir connections are synthetic, as in
/// `OwnershipReapplyTests`.
struct OwnershipSuspensionTests {
  private static let model = ControllerIdentity(vendorID: 0x3537, productID: 0x100B)
  private static let locationID: UInt32 = 0x0021_0000
  private static let identifier = DeviceIdentifier(
    vendorID: 0x3537,
    productID: 0x100B,
    locationID: locationID
  )

  /// Like `HIDDeviceStream`, the backend's disconnect and its new connection reach the manager
  /// after `reloadControllerRecords` returns.
  @Test
  func aRecordReloadThatAdmitsTheControllerAgainKeepsItsSuspension() async throws {
    let (manager, backend, old) = try await Self.suspendedController()
    let new = Self.gameSir()
    await backend.replace(old, with: new)

    await manager.reloadControllerRecords(changing: [Self.model])
    await manager.handleHIDEvent(.disconnected(connection: old))
    await manager.handleHIDEvent(.connected(connection: new, ownership: .exclusive))

    #expect(await manager.deviceInfos[Self.identifier]?.hidConnectionID == new.connectionID)
    #expect(await manager.suspendedControllerIdentities.contains(Self.identifier))
    let pipeline = try #require(await manager.pipelines[Self.identifier])
    #expect(await pipeline.controllerSessionState() == .suspended)
    await manager.stop()
  }

  /// A reload that leaves the connection in place marks nothing, so a later unplug of the same
  /// connection ends the suspension.
  @Test
  func aPhysicalDisconnectAfterAReloadThatKeptTheConnectionEndsTheSuspension() async throws {
    let (manager, _, old) = try await Self.suspendedController()

    await manager.reloadControllerRecords(changing: [Self.model])
    try await Self.waitForHIDInitializations(of: manager)
    let current = try #require(await manager.deviceInfos[Self.identifier]?.hidConnectionID)
    #expect(current == old.connectionID)
    #expect(await manager.ownershipCycledHIDConnections.isEmpty)
    await manager.handleHIDEvent(.disconnected(connection: old))

    #expect(await !manager.suspendedControllerIdentities.contains(Self.identifier))
    await manager.stop()
  }

  /// A suspended GameSir on a started manager whose backend reports it as the only connection.
  private static func suspendedController() async throws -> (
    DeviceManager, ReplacingHIDBackend, HIDDeviceConnection
  ) {
    let scripted = ScriptedHIDAccessBackend()
    await scripted.enableOutputReports()
    await scripted.enableFeatureReports()
    let backend = ReplacingHIDBackend(scripted)
    let manager = DeviceManager(
      dispatcher: HIDRoleEventRecorder(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let connection = gameSir()
    await backend.setSnapshots([connection])
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    _ = try #require(await manager.pipelines[identifier])
    let result = await manager.suspendController(
      vendorID: model.vendorID,
      productID: model.productID,
      runtimeIdentifier: nil
    )
    #expect(result.failure == nil)
    #expect(await manager.suspendedControllerIdentities.contains(identifier))
    return (manager, backend, connection)
  }

  private static func waitForHIDInitializations(of manager: DeviceManager) async throws {
    for _ in 0..<400 where await !manager.hidInitializationTasks.isEmpty {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await manager.hidInitializationTasks.isEmpty)
  }

  private static func gameSir() -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: model.vendorID,
        productID: model.productID,
        productName: "GameSir",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            hostTransport: .usb,
            accessBackend: .ioHID,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ],
        nativePassThrough: false
      ),
      routingLocationID: locationID
    )
  }
}

/// Forwards to the scripted fake. Its ownership re-evaluation swaps each replaced connection in
/// the snapshots and returns the new connections, without sending events.
private actor ReplacingHIDBackend: HIDAccessBackend {
  private let scripted: ScriptedHIDAccessBackend
  private var snapshots: [HIDDeviceConnection] = []
  private var replacements: [UUID: HIDDeviceConnection] = [:]

  init(_ scripted: ScriptedHIDAccessBackend) { self.scripted = scripted }

  func setSnapshots(_ connections: [HIDDeviceConnection]) async {
    snapshots = connections
    await scripted.setConnectionSnapshots(
      connections.map { HIDDeviceConnectionSnapshot(connection: $0, ownership: .exclusive) }
    )
  }

  func replace(_ connection: HIDDeviceConnection, with replacement: HIDDeviceConnection) {
    replacements[connection.connectionID] = replacement
  }

  func reevaluateOwnership(of _: Set<ControllerIdentity>) async -> Set<UUID> {
    let swapped = snapshots.map { replacements.removeValue(forKey: $0.connectionID) ?? $0 }
    let admitted = Set(swapped.map(\.connectionID)).subtracting(snapshots.map(\.connectionID))
    await setSnapshots(swapped)
    return admitted
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> { await scripted.deviceEvents() }

  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await scripted.currentConnectionSnapshots()
  }

  func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setOutputReport(locationID: locationID, report: report)
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setOutputReport(connection: connection, report: report)
  }

  func setFeatureReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setFeatureReport(locationID: locationID, report: report)
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setFeatureReport(connection: connection, report: report)
  }

  func getFeatureReport(
    locationID: UInt32,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await scripted.getFeatureReport(locationID: locationID, request: request)
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await scripted.getFeatureReport(connection: connection, request: request)
  }

  func releaseInputClaim(locationID: UInt32) async -> PhysicalHIDClaimResult {
    await scripted.releaseInputClaim(locationID: locationID)
  }

  func reacquireInputClaim(locationID: UInt32) async -> PhysicalHIDClaimResult {
    await scripted.reacquireInputClaim(locationID: locationID)
  }

  func retryInputClaim(locationID: UInt32) async {
    await scripted.retryInputClaim(locationID: locationID)
  }

  func routeElementValues(connection: HIDDeviceConnection) async {
    await scripted.routeElementValues(connection: connection)
  }
}
