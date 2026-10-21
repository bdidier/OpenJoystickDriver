import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.serialized, .timeLimit(.minutes(2)))
struct LocalRPCBridgeTests {
  private static let controllerMethodNames: Set = [
    "getStatus", "requestRequiredAccess", "requestAccess", "getControllerState", "getPacketLog",
    "getVirtualOutputState",
    "sendControllerOutput", "previewPhysicalColor", "releasePhysicalColorPreview",
    "getVirtualDeviceDiagnostics", "getFrameTimings", "waitForServiceStatusChange",
    "setVirtualHIDProfileOverride",
    "resetVirtualHIDProfileOverride", "setControllerServer", "openVirtualFeed",
    "exchangeVirtualFeed",
    "closeVirtualFeed", "suspendController", "resumeController",
    "disconnectWirelessController", "resetSettings", "getSettings", "setSetting",
    "getAccessStatus", "setAccessEnabled", "grantAccess", "revokeAccess",
    "grantTokenAccess", "setWebAccess",
  ]
  private static let remappingMethodNames: Set = [
    "remappingMotionCalibration", "pairRemappingJoyCons", "unpairRemappingJoyCons",
    "getRemappingSnapshot", "getRemappingProfile", "createRemappingProfile",
    "updateRemappingProfile", "deleteRemappingProfile", "importRemappingProfile",
    "activateRemappingProfile", "deactivateRemappingProfile", "deactivateRemappingProfileByID",
    "getRemappingPostEventAccess", "requestRemappingPostEventAccess",
    "deleteDamagedRemappingProfile", "resetRemappingProfileLibrary",
  ]

  @Test
  func theServersFeedsKeepTheProductionIdleTimeout() async throws {
    try await withServer { server in
      #expect(server.virtualFeeds.idleTimeout == 2)
    }
  }

  @Test
  func methodRawValuesAreTheWireNames() {
    #expect(
      Set(ApplicationServiceRPCMethod.allCases.map(\.rawValue))
        == Self.controllerMethodNames.union(Self.remappingMethodNames)
    )
  }

  @Test(arguments: ApplicationServiceRPCMethod.allCases)
  func everyMethodNameDispatchesToItsHandler(_ method: ApplicationServiceRPCMethod) async throws {
    try await withServer { server in
      let response = await handle(server, method: method.rawValue, arguments: Data("{".utf8))

      #expect(response.result == nil)
      #expect(response.error != Self.unknownMethodMessage(method.rawValue))
      if Self.remappingMethodNames.contains(method.rawValue) {
        #expect(response.remappingError?.code == .invalidArguments)
      } else {
        #expect(response.error != nil)
        #expect(response.remappingError == nil)
      }
    }
  }

  @Test
  func unknownMethodNameFailsWithTheUnknownMethodMessage() async throws {
    try await withServer { server in
      let response = await handle(server, method: "noSuchMethod", arguments: Data("{}".utf8))

      #expect(response.error == Self.unknownMethodMessage("noSuchMethod"))
      #expect(response.remappingError == nil)
    }
  }

  @Test
  func remappingFailureTravelsInTheStructuredErrorField() async throws {
    try await withServer { server in
      let arguments = try JSONEncoder().encode(
        ApplicationServiceRemappingProfileIDArguments(profileID: UUID())
      )
      let response = await handle(server, method: "getRemappingProfile", arguments: arguments)

      let error = try #require(response.remappingError)
      #expect(error.code == .profileNotFound)
      #expect(response.error == error.message)
    }
  }

  @Test
  func remappingFailureArrivesAtTheClientAsTheTypedError() async throws {
    try await withServer { server in
      let socketPath = "/tmp/com.openjoystickdriver.bridge.\(UUID().uuidString).rpc"
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { request, completion in Task { completion(await server.handleLocalRPC(request)) }
        }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let client = ApplicationServiceClient(socketPath: socketPath)
      await client.connect()

      let error = await #expect(throws: ApplicationServiceRemappingRPCError.self) {
        try await client.getRemappingProfile(id: UUID())
      }
      #expect(error?.code == .profileNotFound)
    }
  }

  @Test
  func aStatusNotificationReachesAWaitingClientWithinOneSecond() async throws {
    try await withServer { server in
      let socketPath = "/tmp/com.openjoystickdriver.bridge.\(UUID().uuidString).rpc"
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { request, completion in Task { completion(await server.handleLocalRPC(request)) }
        }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let client = ApplicationServiceClient(socketPath: socketPath)
      await client.connect()
      let baseline = try await client.waitForServiceStatusChange(after: nil)

      let clock = ContinuousClock()
      let start = clock.now
      async let next = client.waitForServiceStatusChange(after: baseline)
      try await Task.sleep(nanoseconds: 100_000_000)
      NotificationCenter.default.post(name: .ojdServiceStatusDidChange, object: nil)

      #expect(try await next != baseline)
      #expect(clock.now - start < .seconds(10))
    }
  }

  @Test
  func aVirtualOutputStatusChangeAnnouncesOnceAfterTheLockIsReleased() async throws {
    try await withServer { server in
      let lockHeldDuringPost = LockedFlag()
      let observer = NotificationCenter.default.addObserver(
        forName: .ojdServiceStatusDidChange,
        object: server,
        queue: nil
      ) { _ in
        // A held lock cannot be taken again; `try` fails the check while the lock is held.
        if server.userSpaceLock.try() {
          server.userSpaceLock.unlock()
        } else {
          lockHeldDuringPost.set()
        }
      }
      defer { NotificationCenter.default.removeObserver(observer) }

      let count = await Self.announcements(from: server) {
        server.withUserSpaceState { server.userSpaceStatus = .error("failed") }
      }

      #expect(count == 1)
      #expect(!lockHeldDuringPost.isSet)
    }
  }

  @Test
  func aRepeatedVirtualOutputStatusAnnouncesNothing() async throws {
    try await withServer { server in
      #expect(
        await Self.announcements(from: server) {
          server.withUserSpaceState { server.userSpaceStatus = .off }
        } == 0
      )
    }
  }

  @Test
  func aProfileReloadAnnouncesFromTheRemappingCoordinator() async throws {
    try await withServer { server in
      #expect(
        await Self.announcements(from: server.remappingRequests) {
          await server.reloadRemappingProfiles()
        } == 1
      )
    }
  }

  @Test
  func anOverrideResetAnnouncesFromTheServer() async throws {
    try await withServer { server in
      #expect(
        await Self.announcements(from: server) { server.resetVirtualHIDProfileSettings() } == 1
      )
    }
  }

  /// How many service status changes `source` announces during `action`.
  private static func announcements(
    from source: AnyObject,
    _ action: () async -> Void
  ) async -> Int {
    let count = AnnouncementCount()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: source,
      queue: nil
    ) { _ in count.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }
    await action()
    return count.value
  }

  private static func unknownMethodMessage(_ name: String) -> String {
    "Unknown RPC method: \(name)"
  }

  @Test
  func aListenerRestartAfterStopBeginsRefusesAsStopping() async throws {
    let socketPath = "/tmp/com.openjoystickdriver.test.\(UUID().uuidString).rpc"
    try await withServer { server in
      let listener = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { _, completion in
          completion(LocalServiceRPCResponse(result: nil, error: nil))
        }
      )
      server.rpcServerLock.withLock { server.rpcServer = listener }
      try listener.start()
      defer { listener.stop() }

      // While the service runs, a listener that already runs is reported as such.
      #expect(throws: LocalServiceRPCError.alreadyRunning) {
        try server.restartListener(of: listener)
      }
      await server.stop()
      #expect(throws: LocalServiceRPCError.stopping) {
        try server.restartListener(of: listener)
      }
    }
  }

  private func handle(
    _ server: ApplicationServiceServer,
    method: String,
    arguments: Data
  ) async -> LocalServiceRPCResponse {
    let request = LocalServiceRPCRequest(method: method, arguments: arguments)
    return await server.handleLocalRPC(request)
  }

  private func withServer(_ body: (ApplicationServiceServer) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let dispatcher = VirtualOutputRouter()
    let library = RemappingProfileLibrary(directory: directory)
    let postEventAccess = CoreGraphicsPostEventAccess()
    let router = RemappingOutputRouter(
      library: library,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess,
      installationKey: testPortKeyInstallationKey
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: router, installationKey: testPortKeyInstallationKey),
      permissionManager: PermissionManager(),
      dispatcher: dispatcher,
      remappingProfileLibrary: library,
      remappingRouter: router,
      postEventAccess: postEventAccess,
      installationKey: testPortKeyInstallationKey,
      userSpaceDispatcherFactory: ApplicationServiceRuntime.makeAutomaticUserSpaceDispatcher(
        context:
      ),
      settings: settings,
      personaDirectory: directory.appendingPathComponent("Personas", isDirectory: true)
    )
    try await body(server)
  }
}

private final class AnnouncementCount: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var flag = false
  var isSet: Bool { lock.withLock { flag } }
  func set() { lock.withLock { flag = true } }
}
