import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct USBPipelineRecoveryTests {
  let identifier = LogicalControllerID(
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 7,
    interfaceNumber: 0
  )
  let device = USBTransportDevice(
    route: .ioUSBHost,
    serviceID: 1,
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 7
  )

  @Test
  func disconnectedReadClosesOnceAndReopensOneSession() async {
    let first = RecoveryUSBSession(readError: .disconnected)
    let second = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [first, second])
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryInputParser(),
      dispatcher: RecoveryOutputDispatcher(),
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 1_000_000
      )
    )

    let start = Task { await pipeline.start() }
    await waitUntil("provider.openCount == 2") { await provider.openCount == 2 }
    #expect(await first.closeCount == 1)

    await pipeline.stop()
    await start.value
    #expect(await first.closeCount == 1)
    #expect(await second.closeCount == 1)
  }

  @Test
  func accessDeniedReadRetriesAfterContentionDelayAndNeutralizesOnce() async {
    let first = RecoveryUSBSession(
      readResults: [.success([1]), .failure(.accessDenied)],
      readError: .timeout
    )
    let second = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [first, second])
    let parser = RecoveryInputParser()
    let dispatcher = RecoveryOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: parser,
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 60_000_000_000,
        reconnectMaximumDelayNanoseconds: 60_000_000_000,
        accessContentionDelayNanoseconds: 200_000_000
      )
    )

    let start = Task { await pipeline.start() }
    // A read access denial uses the access-contention delay, not reconnect backoff.
    await waitUntil("the second open") { await provider.openCount == 2 }
    await waitUntil("dispatcher.ownershipReports.contains(.accessDenied)") {
      dispatcher.ownershipReports.contains(.accessDenied)
    }
    #expect(await first.closeCount == 1)
    #expect(await provider.openedDevices == [device, device])
    await waitUntil("parser.resetCount == 3") { parser.resetCount == 3 }
    #expect(parser.resetCount == 3)
    let states = [ControllerState.neutral] + dispatcher.dispatchedStates
    let releases = zip(states, states.dropFirst()).filter {
      $0.pressed.contains(.south) && !$1.pressed.contains(.south)
    }
    #expect(releases.count == 1)

    await pipeline.stop()
    await start.value
    #expect(await first.closeCount == 1)
    #expect(await second.closeCount == 1)
  }

  @Test
  func stoppingAfterReadAccessDenialPreventsReopen() async {
    let denied = RecoveryUSBSession(readError: .accessDenied)
    let provider = RecoveryUSBProvider(sessions: [denied])
    let dispatcher = RecoveryOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 10_000_000_000
      )
    )

    let start = Task { await pipeline.start() }
    await waitUntil("dispatcher.ownershipReports.contains(.accessDenied)") {
      dispatcher.ownershipReports.contains(.accessDenied)
    }
    let runTask = await pipeline.usbRunTaskForTesting()
    await pipeline.stop()
    await start.value
    await runTask?.value

    #expect(await provider.openCount == 1)
    #expect(await denied.closeCount == 1)
  }

  @Test
  func stopWaitsForPendingAccessDeniedReportThenPublishesUnknown() async {
    let denied = RecoveryUSBSession(readError: .accessDenied)
    let provider = RecoveryUSBProvider(sessions: [denied])
    let gate = RecoveryOwnershipGate()
    let dispatcher = RecoveryGatedOutputDispatcher(gate: gate)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 10_000_000_000
      )
    )

    await pipeline.start()
    let runTask = await pipeline.usbRunTaskForTesting()
    await waitUntil("the access-denied report starts") { await gate.accessDeniedReportStarted }

    let stopCompletion = RecoveryStopCompletion()
    let stopTask = Task {
      await pipeline.stop()
      await stopCompletion.markComplete()
    }
    await waitUntil("the stop cleanup runs") { dispatcher.didStopController }
    let stoppedBeforeReportCompleted = await stopCompletion.isComplete
    await gate.release()
    await stopTask.value
    await runTask?.value

    #expect(!stoppedBeforeReportCompleted)
    #expect(await stopCompletion.isComplete)
    #expect(dispatcher.ownershipReports.suffix(2) == [.accessDenied, .unknown])
    #expect(await denied.closeCount == 1)
  }

  @Test
  func systemSleepTearsDownUSBControllersAndWakeReattachesThroughDetection() async {
    let first = RecoveryUSBSession(readError: .timeout)
    let second = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [first, second], devices: [device])
    let manager = makeManager(using: provider)
    await manager.start()
    await waitUntil("first.writeCount > 0") { await first.writeCount > 0 }
    #expect(await manager.connectedLogicalControllerIDs() == [identifier])

    await manager.systemWillSleep()
    #expect(await manager.isSystemSleeping)
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.detectionTasks.isEmpty)
    #expect(await manager.permissionWatchTask == nil)
    #expect(await first.closeCount == 1)

    await manager.systemDidWake()
    #expect(!(await manager.isSystemSleeping))
    await waitUntil("second.writeCount > 0") { await second.writeCount > 0 }
    #expect(await manager.connectedLogicalControllerIDs() == [identifier])
    #expect(await provider.openedDevices == [device, device])
    await manager.stop()
    #expect(await second.closeCount == 1)
  }

  @Test
  func startRequestedDuringSleepRunsOnlyAfterWake() async {
    let manager = makeManager(using: RecoveryUSBProvider(sessions: []))
    await manager.start()
    await manager.systemWillSleep()

    await manager.start()
    #expect(await manager.detectionTasks.isEmpty)
    #expect(await manager.permissionWatchTask == nil)

    await manager.systemDidWake()
    #expect(!(await manager.detectionTasks.isEmpty))
    #expect(await manager.permissionWatchTask != nil)
    await manager.stop()
  }

  @Test
  func stopDuringSleepPreventsRestartOnWake() async {
    let manager = makeManager(using: RecoveryUSBProvider(sessions: []))
    await manager.start()
    await manager.systemWillSleep()
    await manager.stop()

    await manager.systemDidWake()
    #expect(!(await manager.isSystemSleeping))
    #expect(await manager.detectionTasks.isEmpty)
    #expect(await manager.permissionWatchTask == nil)

    await manager.start()
    #expect(!(await manager.detectionTasks.isEmpty))
    await manager.stop()
  }

  @Test
  func sleepDuringUSBAdmissionLeavesNoControllerAndWakeReadmitsIt() async {
    let session = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [session], devices: [device])
    await provider.gateNextResolution()
    let manager = makeManager(using: provider)
    await manager.start()
    await waitUntil("provider.resolutionGateReached") { await provider.resolutionGateReached }
    let admittingDetection = await manager.detectionTasks.first

    await manager.systemWillSleep()
    await provider.releaseResolutionGate()
    await admittingDetection?.value
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await provider.openCount == 0)

    await manager.systemDidWake()
    await waitUntil("session.writeCount > 0") { await session.writeCount > 0 }
    #expect(await manager.connectedLogicalControllerIDs() == [identifier])
    await manager.stop()
  }

  func makeManager(
    using provider: any USBTransportProvider,
    dispatcher: RecoveryOutputDispatcher = RecoveryOutputDispatcher()
  ) -> DeviceManager {
    DeviceManager(
      dispatcher: dispatcher,
      hidManager: HIDManager(backend: RecoveryHIDBackend()),
      usbTransportProvider: provider
    )
  }
}
