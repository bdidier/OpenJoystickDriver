import OpenJoystickDriverTestSupport
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// A server whose automatic dispatcher builds retarget probes and reads overrides from isolated
/// settings.
extension VirtualOutputTests {
  func profileOverrideServer(
    _ identifiers: [LogicalControllerID] = [LogicalControllerID(vendorID: 1, productID: 2)],
    failure: (VirtualHIDProfileID, ProfileRetargetFailure)? = nil,
    outputEnabled: Bool = true,
    activationGate: (VirtualHIDProfileID, InstallationGate)? = nil,
    timeouts: VirtualOutputTransitionTimeouts = .standard,
    clock: VirtualOutputTransitionClock = .system,
    configure: (URL) -> Void = { _ in }
  ) async throws -> ProfileOverrideServerFixture {
    let suiteName = "OpenJoystickDriverTests.ProfileOverrideRPC.\(UUID().uuidString)"
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let personaDirectory = MacOSDataDirectory().url(for: .temporary)
      .appendingPathComponent(suiteName, isDirectory: true)
    configure(personaDirectory)
    let store = VirtualHIDProfileOverrideStore(directory: personaDirectory)
    let log = RetargetEventLog()
    let descriptions = provider(identifiers)
    let overrideProvider: @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? =
      { store.override(vendorID: $0.vendorID, productID: $0.productID, unit: $0.portKey?.rawValue) }
    let dispatcher = VirtualOutputRouter()
    let profileLibrary = RemappingProfileLibrary(
      directory: RootedDataDirectory.temporary().url(for: .applicationData)
    )
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess,
      installationKey: testPortKeyInstallationKey
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(
        dispatcher: remappingRouter,
        installationKey: testPortKeyInstallationKey
      ),
      permissionManager: PermissionManager(),
      dispatcher: dispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      installationKey: testPortKeyInstallationKey,
      userSpaceDispatcherFactory: { _ in
        AutomaticUserSpaceOutputDispatcher(
          deviceManager: DeviceManager(
            dispatcher: LoggingOutputDispatcher(),
            installationKey: testPortKeyInstallationKey
          ),
          ownershipProvider: { _ in .exclusiveRawUSB },
          builder: { profile in
            let backend = RetargetBackendProbe(
              profile: profile,
              log: log,
              failsActivation: failure.map { $0.0 == profile && $0.1 == .activation } ?? false,
              activationGate: activationGate.flatMap { $0.0 == profile ? $0.1 : nil }
            )
            log.append(backend)
            return backend
          },
          descriptionsProvider: descriptions,
          overrideProvider: overrideProvider
        )
      },
      connectedIdentifierProvider: { identifiers },
      virtualOutputTransitionTimeouts: timeouts,
      virtualOutputTransitionClock: clock,
      settings: settings,
      personaDirectory: personaDirectory
    )
    if outputEnabled { _ = await server.activateVirtualOutputBackendForCurrentDevices() }
    return ProfileOverrideServerFixture(
      server: server,
      personaDirectory: personaDirectory,
      log: log
    )
  }

  @Test
  func settingAnOverridePersistsAndRetargetsTheController() async throws {
    let fixture = try await profileOverrideServer()

    let result = await fixture.change(.set("SDLCompatible"))

    #expect(
      result
        == VirtualHIDProfileOverrideResult(
          requested: .sdlCompatible,
          live: .sdlCompatible,
          source: .override,
          failure: nil
        )
    )
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .sdlCompatible)
    #expect(fixture.log.built().map(\.profile) == [.generic, .sdlCompatible])
    await fixture.tearDown()
  }

  @Test
  func resettingAnOverrideReturnsTheControllerToAutomaticSelection() async throws {
    let fixture = try await profileOverrideServer()
    _ = await fixture.change(.set("SDLCompatible"))

    let result = await fixture.change(.reset)

    #expect(
      result
        == VirtualHIDProfileOverrideResult(
          requested: nil,
          live: .generic,
          source: .automatic,
          failure: nil
        )
    )
    #expect(fixture.store.override(vendorID: 1, productID: 2) == nil)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func anUnknownProfileIsRejectedWithoutPersisting() async throws {
    let fixture = try await profileOverrideServer()

    let result = await fixture.change(.set("xone-hid"))

    #expect(result.failure == .unknownProfile)
    #expect(result.requested == nil)
    #expect(result.live == .generic)
    #expect(fixture.store.files.isEmpty)
    #expect(fixture.log.built().count == 1)
    await fixture.tearDown()
  }

  @Test
  func anUnmatchedControllerIsNotFoundAndNothingIsPersisted() async throws {
    let fixture = try await profileOverrideServer()

    let otherModel = await fixture.change(
      .set("SDLCompatible"),
      controller: .model(ControllerModelID(vendorID: 3, productID: 2))
    )
    let otherSession = await fixture.change(
      .set("SDLCompatible"),
      controller: .session(.fixture("missing"))
    )

    #expect(otherModel.failure == .controllerNotFound)
    #expect(otherSession.failure == .controllerNotFound)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func disabledOutputStillPersistsTheOverride() async throws {
    let fixture = try await profileOverrideServer(outputEnabled: false)

    let result = await fixture.change(.set("SDLCompatible"))

    #expect(
      result
        == VirtualHIDProfileOverrideResult(
          requested: .sdlCompatible,
          live: nil,
          source: .override,
          failure: .outputDisabled
        )
    )
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .sdlCompatible)
    await fixture.tearDown()
  }

  @Test
  func aStoppedServerRejectsOverrideChangesWithoutPersisting() async throws {
    let fixture = try await profileOverrideServer()
    await fixture.server.stop()

    let result = await fixture.change(.set("SDLCompatible"))

    #expect(result.failure == .serverStopped)
    #expect(result.requested == .sdlCompatible)
    #expect(fixture.store.files.isEmpty)
    await fixture.tearDown()
  }

  @Test
  func failedActivationRestoresThePriorStoredOverride() async throws {
    let fixture = try await profileOverrideServer(failure: (.generic, .activation)) {
      VirtualHIDProfileOverrideStore(directory: $0).setSDLCompatibleForTest()
    }
    #expect(fixture.log.built().map(\.profile) == [.sdlCompatible])

    let result = await fixture.change(.set("Generic"))

    guard case .activationFailed(let detail) = result.failure else {
      Issue.record("Expected activation-failed, got \(String(describing: result.failure))")
      return
    }
    #expect(!detail.isEmpty)
    #expect(result.requested == .generic)
    #expect(result.live == .sdlCompatible)
    #expect(result.source == .override)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .sdlCompatible)
    #expect(fixture.log.built().first?.closed == false)
    await fixture.tearDown()
  }

  @Test
  func anOverrideRetargetsEveryControllerOfTheModel() async throws {
    let first = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
    let second = LogicalControllerID(vendorID: 1, productID: 2, locationID: 2)
    let fixture = try await profileOverrideServer([first, second])

    let result = await fixture.change(.set("SDLCompatible"))
    let unmatched = await fixture.change(.reset, controller: .session(.fixture("missing")))

    #expect(result.failure == nil)
    #expect(result.live == .sdlCompatible)
    let automatic = fixture.server.automaticUserSpaceDispatcher()
    for identifier in [first, second] {
      let state = automatic?.profileState(for: identifier)
      #expect(state?.selection?.profileID == .sdlCompatible)
    }
    #expect(unmatched.failure == .controllerNotFound)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .sdlCompatible)
    await fixture.tearDown()
  }

  @Test
  func overrideRequestsRoundTripThroughTheLocalRPCBridge() async throws {
    let fixture = try await profileOverrideServer()
    let set = try await localRPC(
      fixture.server,
      method: "setVirtualHIDProfileOverride",
      arguments: LocalServiceRPCVirtualHIDProfileOverrideArguments(
        controller: .model(ControllerModelID(vendorID: 1, productID: 2)),
        profile: "SDLCompatible"
      )
    )
    let reset = try await localRPC(
      fixture.server,
      method: "resetVirtualHIDProfileOverride",
      arguments: LocalServiceRPCDeviceArguments(
        controller: .model(ControllerModelID(vendorID: 1, productID: 2))
      )
    )

    #expect(
      set
        == VirtualHIDProfileOverrideResult(
          requested: .sdlCompatible,
          live: .sdlCompatible,
          source: .override,
          failure: nil
        )
    )
    #expect(
      reset
        == VirtualHIDProfileOverrideResult(
          requested: nil,
          live: .generic,
          source: .automatic,
          failure: nil
        )
    )
    await fixture.tearDown()
  }

  private func localRPC(
    _ server: ApplicationServiceServer,
    method: String,
    arguments: some Encodable
  ) async throws -> VirtualHIDProfileOverrideResult {
    let envelope: [String: String] = [
      "method": method, "arguments": try JSONEncoder().encode(arguments).base64EncodedString(),
    ]
    let request = try JSONDecoder().decode(
      LocalServiceRPCRequest.self,
      from: JSONEncoder().encode(envelope)
    )
    let response = await server.handleLocalRPC(request)
    let data = try #require(response.result, "\(String(describing: response.error))")
    return try JSONDecoder().decode(VirtualHIDProfileOverrideResult.self, from: data)
  }

  @Test
  func aTimedOutRetargetRestoresThePriorStoredOverride() async throws {
    let gate = InstallationGate()
    let fixture = try await profileOverrideServer(
      activationGate: (.generic, gate),
      timeouts: VirtualOutputTransitionTimeouts(
        stageNanoseconds: 2_000_000_000,
        perControllerNanoseconds: 50_000_000,
        totalNanoseconds: 10_000_000_000
      )
    ) { VirtualHIDProfileOverrideStore(directory: $0).setSDLCompatibleForTest() }

    let result = await fixture.change(.set("Generic"))

    guard case .activationFailed = result.failure else {
      Issue.record("Expected activation-failed, got \(String(describing: result.failure))")
      return
    }
    #expect(result.live == .sdlCompatible)
    #expect(fixture.store.override(vendorID: 1, productID: 2) == .sdlCompatible)
    await gate.release()
    await fixture.tearDown()
  }
}
