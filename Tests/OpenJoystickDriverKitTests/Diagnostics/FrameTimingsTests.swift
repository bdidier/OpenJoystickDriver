import Foundation
import Testing

@testable import OpenJoystickDriverKit

private final class StickParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
  let sessionPlan = DriverSessionPlan(inputReportLivenessTimeoutNanoseconds: 1_000_000_000)
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    ControllerEvent(data.first == 1 ? [.rightStick(x: 1, y: 0)] : [], at: receivedAt.nanoseconds)
  }
}

private struct PublishFailure: Error {}

/// Publishes like the virtual device does: reports the publication only when it succeeds.
final class PublishingDispatcher: OutputDispatcher, @unchecked Sendable {
  enum Outcome: Sendable { case publishes, fails, suppressed }

  var suppressOutput = false
  private let outcome: Outcome
  init(_ outcome: Outcome) { self.outcome = outcome }

  func dispatch(
    _: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: LogicalControllerID
  ) {}

  func activateOutput(for _: LogicalControllerID) {}

  func dispatchPublishing(
    _: ControllerEvent,
    labels _: ControllerButtonLabels,
    from _: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) throws {
    switch outcome {
    case .publishes: onPublished()
    case .fails: throw PublishFailure()
    case .suppressed: return
    }
  }
}

struct FrameTimingsTests {
  private let identifier = LogicalControllerID(vendorID: 1, productID: 2)

  @Test
  func aDispatchedFrameListsEveryStageItReachedInPipelineOrder() async {
    let ticks = Locked<UInt64>(1_000)
    let recorder = FrameTimingRecorder()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: StickParser(),
      dispatcher: PublishingDispatcher(.publishes),
      frameTimings: recorder
    ) {
      ticks.withLock { value in
        value += 10
        return value
      }
    }
    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))

    let frames = recorder.frames(for: identifier)
    #expect(frames.count == 1)
    let stages = frames.first?.stages ?? []
    #expect(
      stages.map(\.stage) == [.read, .parse, .dispatch, .deliveryVirtualDevice],
      "\(stages)"
    )
    #expect(stages.map(\.nanoseconds) == stages.map(\.nanoseconds).sorted())
    #expect(Set(stages.map(\.nanoseconds)).count == stages.count)
    await pipeline.stop()
    #expect(recorder.frames(for: identifier).isEmpty)
  }

  @Test(arguments: [PublishingDispatcher.Outcome.fails, .suppressed])
  func aFrameThatNeverReachedTheVirtualDeviceHasNoDeliveryStage(
    outcome: PublishingDispatcher.Outcome
  ) async {
    let ticks = Locked<UInt64>(1_000)
    let recorder = FrameTimingRecorder()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: StickParser(),
      dispatcher: PublishingDispatcher(outcome),
      frameTimings: recorder
    ) {
      ticks.withLock { value in
        value += 10
        return value
      }
    }
    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))

    let stages = recorder.frames(for: identifier).first?.stages.map(\.stage)
    #expect(stages == [.read, .parse, .dispatch], "\(String(describing: stages))")
    await pipeline.stop()
  }

  @Test
  func theRouterReportsAPublicationOnlyWhileOutputIsNotSuppressed() async throws {
    let router = VirtualOutputRouter()
    router.setBackend(PublishingDispatcher(.publishes))
    let published = Locked(0)
    let event = ControllerEvent([], at: 1)
    let count: @Sendable () -> Void = { published.withLock { $0 += 1 } }

    try await router.dispatchPublishing(
      event,
      labels: .standard,
      from: identifier,
      onPublished: count
    )
    router.suppressOutput = true
    try await router.dispatchPublishing(
      event,
      labels: .standard,
      from: identifier,
      onPublished: count
    )

    #expect(published.withLock { $0 } == 1)
  }

  @Test
  func endpointDeliveryAttachesToTheNewestFrame() {
    let recorder = FrameTimingRecorder()
    recorder.parsed(for: identifier, read: 1, parse: 2)
    let sequence = recorder.dispatched(for: identifier, at: 3)
    recorder.virtualDeviceDelivered(sequence: sequence ?? 99, for: identifier, at: 4)
    recorder.endpointDelivered(for: identifier, at: 5)

    #expect(
      recorder.frames(for: identifier).first?.stages.map(\.stage) == [
        .read, .parse, .dispatch, .deliveryVirtualDevice, .deliveryEndpoint,
      ]
    )
  }

  @Test
  func theRingKeepsOnlyTheNewestFrames() {
    let recorder = FrameTimingRecorder()
    for index in 0..<(FrameTimingRecorder.capacity + 3) {
      recorder.parsed(for: identifier, read: UInt64(index), parse: UInt64(index))
      _ = recorder.dispatched(for: identifier, at: UInt64(index))
    }

    let sequences = recorder.frames(for: identifier).map(\.sequence)
    #expect(sequences.count == FrameTimingRecorder.capacity)
    #expect(sequences.first == 3)
    #expect(sequences.last == UInt64(FrameTimingRecorder.capacity + 2))
  }

  @Test
  func aDispatchWithoutAParsedReportLeavesNoFrame() {
    let recorder = FrameTimingRecorder()

    #expect(recorder.dispatched(for: identifier, at: 1) == nil)
    #expect(recorder.frames(for: identifier).isEmpty)
  }
}
