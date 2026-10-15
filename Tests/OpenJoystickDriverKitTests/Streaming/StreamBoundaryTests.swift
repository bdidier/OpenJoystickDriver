import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The source and sink boundary: what each shape of frame reaches, and what a sink refuses.
struct StreamBoundaryTests {
  private static let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  private final class RecordingDispatcher: OutputDispatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var published: [ControllerEvent] = []
    var suppressOutput = false

    func dispatch(
      _ event: ControllerEvent,
      labels _: ControllerButtonLabels,
      from _: LogicalControllerID
    ) async {  // swiftlint:disable:this async_without_await
      lock.withLock { published.append(event) }
    }

    func activateOutput(for _: LogicalControllerID) {}

    func events() -> [ControllerEvent] { lock.withLock { published } }
  }

  private final class BareSink: OutputSink, Sendable {
    let destination = OutputDestination.physicalOutput
  }

  @Test
  func aSinkRefusesWhatItDoesNotConsume() async {
    let sink = BareSink()
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await sink.consume(.gamepad(RemappingGamepadState(), for: Self.identifier)) {}
    }
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await sink.consume(.stopRumble, for: Self.identifier)
    }
  }

  @Test
  func aDispatcherConsumesControllerFrames() async throws {
    let dispatcher = RecordingDispatcher()
    let delivered = Locked(0)
    let event = ControllerEvent([.leftStick(x: 0.5, y: 0)])

    try await dispatcher.consume(
      .controller(event, labels: .standard, from: Self.identifier)
    ) { delivered.withLock { $0 += 1 } }

    #expect(dispatcher.destination == .virtualDevice)
    #expect(dispatcher.events().count == 1)
    // The default `dispatchPublishing` never reports a publication, so no delivery is stamped.
    #expect(delivered.withLock { $0 } == 0)
  }

  @Test
  func aDispatcherWithoutAGamepadSinkRefusesGamepadFrames() async {
    let dispatcher = RecordingDispatcher()
    await #expect(throws: StreamBoundaryError.unsupported(.virtualDevice)) {
      try await dispatcher.consume(.gamepad(RemappingGamepadState(), for: Self.identifier)) {}
    }
  }

  @Test
  func aPipelineIsAPhysicalControllerSourceThatFeedsItsDispatcherThroughTheSink() async {
    let dispatcher = RecordingDispatcher()
    let pipeline = DevicePipeline(
      identifier: Self.identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches([[.leftStick(x: 0.5, y: 0)]]),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await pipeline.start()
    _ = await pipeline.feedHIDData(Data([0]))
    await pipeline.stop()

    #expect(pipeline.origin == .physicalController)
    #expect(pipeline.sink === dispatcher)
    #expect(dispatcher.events().contains { $0.state.leftStick != .center })
  }
}
