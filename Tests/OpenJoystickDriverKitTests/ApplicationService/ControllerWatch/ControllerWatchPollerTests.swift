import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerWatchPollerTests {
  @Test
  func reportsConnectionsAndOnlyChangedInput() async throws {
    let source = FakeWatchSource()
    source.set(devices: ["pad-1", "pad-2"], state: ControllerState(pressed: [.south]))
    var poller = ControllerWatchPoller(source: source)

    let first = try await poller.poll(now: 0, includeOutput: false)
    let second = try await poller.poll(now: 16_000_000, includeOutput: false)
    source.set(devices: ["pad-1"], state: ControllerState(pressed: [.east]))
    let third = try await poller.poll(now: 32_000_000, includeOutput: false)
    let fourth = try await poller.poll(
      now: ControllerWatchPoller.deviceListInterval,
      includeOutput: false
    )

    #expect(
      first.map(\.summary) == [
        "ADDED \(token("pad-1"))", "ADDED \(token("pad-2"))", "MODIFIED \(token("pad-1"))",
        "MODIFIED \(token("pad-2"))",
      ]
    )
    #expect(second.isEmpty)
    // The list is read again only after the interval, so pad-2 is still read until then.
    #expect(third.map(\.summary) == ["MODIFIED \(token("pad-1"))", "MODIFIED \(token("pad-2"))"])
    #expect(fourth.map(\.summary) == ["DELETED \(token("pad-2"))"])
    #expect(first[0].event.object.id == token("pad-1"))
    #expect(first[0].event.object.input == nil)
    #expect(first[2].event.object.input == ControllerState(pressed: [.south]))
    // A deleted controller's object is the last one the watch saw.
    #expect(fourth[0].event.object.input == ControllerState(pressed: [.east]))
  }

  @Test
  func readsOutputOnlyWhenAsked() async throws {
    let source = FakeWatchSource()
    source.set(devices: ["pad-1"], state: ControllerState())
    var poller = ControllerWatchPoller(source: source)

    let without = try await poller.poll(now: 0, includeOutput: false)
    let with = try await poller.poll(now: 16_000_000, includeOutput: true)

    #expect(source.outputReads == 1)
    #expect(without.last?.event.object.output == nil)
    #expect(with.map(\.summary) == ["MODIFIED \(token("pad-1"))"])
    #expect(with.last?.event.object.output == source.output)
  }

  /// The output is read before the input, so an object never holds an output newer than its input.
  @Test
  func readsOutputBeforeInput() async throws {
    let source = FakeWatchSource()
    source.set(devices: ["pad-1"], state: ControllerState())
    var poller = ControllerWatchPoller(source: source)

    _ = try await poller.poll(now: 0, includeOutput: true)

    #expect(source.readOrder == ["output", "state"])
  }
}

extension ControllerWatchPoller.Update {
  var summary: String { "\(event.type.rawValue) \(event.id)" }
}
