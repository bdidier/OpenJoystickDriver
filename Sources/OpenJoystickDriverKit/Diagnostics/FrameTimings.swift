import Foundation

/// One stage a controller frame passes through, in pipeline order. The raw values are the stable
/// identifiers that `ojd diagnose` prints and `cli-output.schema.json` lists.
public enum FrameStage: String, Codable, CaseIterable, Sendable {
  /// The report arrived from the controller.
  case read = "Read"
  /// The protocol driver finished parsing the report into a controller event.
  case parse = "Parse"
  /// The pipeline handed the event to the output dispatcher.
  case dispatch = "Dispatch"
  /// The output dispatcher finished with the event, so the virtual device has the report.
  case deliveryVirtualDevice = "DeliveryVirtualDevice"
  /// The endpoint sent a stream line carrying the controller's state, which may be newer than the
  /// frame it is recorded on: the endpoint reads the latest state on its own poll.
  case deliveryEndpoint = "DeliveryEndpoint"
}

/// The time a frame reached `stage`, in nanoseconds of the monotonic uptime clock.
public struct FrameStageTime: Codable, Equatable, Sendable {
  public let stage: FrameStage
  public let nanoseconds: UInt64

  public init(stage: FrameStage, nanoseconds: UInt64) {
    self.stage = stage
    self.nanoseconds = nanoseconds
  }
}

/// The stages one frame reached, in the order it reached them.
public struct FrameTiming: Codable, Equatable, Sendable {
  /// Counts the frames that reached dispatch for this controller since its pipeline started.
  public let sequence: UInt64
  public let stages: [FrameStageTime]

  public init(sequence: UInt64, stages: [FrameStageTime]) {
    self.sequence = sequence
    self.stages = stages
  }
}

/// The newest frames of one connected controller, oldest first.
public struct ControllerFrameTimings: Codable, Equatable, Sendable {
  /// The ID from `ojd controller list`.
  public let controller: String
  public let name: String
  public let frames: [FrameTiming]

  public init(controller: String, name: String, frames: [FrameTiming]) {
    self.controller = controller
    self.name = name
    self.frames = frames
  }
}

/// The result of `ApplicationServiceClient.getFrameTimings()`.
public struct ApplicationServiceFrameTimingsPayload: Codable, Equatable, Sendable {
  public let controllers: [ControllerFrameTimings]

  public init(controllers: [ControllerFrameTimings]) { self.controllers = controllers }
}

/// Records when frames reach each pipeline stage, for `ojd diagnose`.
///
/// It keeps the newest ``capacity`` frames per controller, so memory stays bounded. A frame
/// enters the ring when it is dispatched; reports that never reach dispatch leave no entry.
public final class FrameTimingRecorder: Sendable {
  /// The frames kept per controller.
  public static let capacity = 8

  private struct Pending {
    let read: UInt64
    let parse: UInt64
  }

  private struct Track {
    var pending: Pending?
    var nextSequence: UInt64 = 0
    var frames: [FrameTiming] = []

    mutating func append(_ stage: FrameStage, at nanoseconds: UInt64, toFrameAt index: Int) {
      let frame = frames[index]
      frames[index] = FrameTiming(
        sequence: frame.sequence,
        stages: frame.stages + [FrameStageTime(stage: stage, nanoseconds: nanoseconds)]
      )
    }
  }

  private let tracks = Locked<[LogicalControllerID: Track]>([:])

  public init() {}

  /// Notes the newest parsed report of `identifier`; a later report replaces it.
  func parsed(for identifier: LogicalControllerID, read: UInt64, parse: UInt64) {
    tracks.withLock { $0[identifier, default: Track()].pending = Pending(read: read, parse: parse) }
  }

  /// Starts a frame from the pending report at the dispatch stage and returns its sequence, or nil
  /// when no parsed report is pending.
  func dispatched(for identifier: LogicalControllerID, at nanoseconds: UInt64) -> UInt64? {
    tracks.withLock { tracks in
      guard var track = tracks[identifier], let pending = track.pending else { return nil }
      track.pending = nil
      let sequence = track.nextSequence
      track.nextSequence += 1
      track.frames.append(
        FrameTiming(
          sequence: sequence,
          stages: [
            FrameStageTime(stage: .read, nanoseconds: pending.read),
            FrameStageTime(stage: .parse, nanoseconds: pending.parse),
            FrameStageTime(stage: .dispatch, nanoseconds: nanoseconds),
          ]
        )
      )
      if track.frames.count > Self.capacity { track.frames.removeFirst() }
      tracks[identifier] = track
      return sequence
    }
  }

  /// Adds the virtual device delivery to the frame `sequence`, unless the ring already dropped it.
  func virtualDeviceDelivered(
    sequence: UInt64,
    for identifier: LogicalControllerID,
    at nanoseconds: UInt64
  ) {
    tracks.withLock { tracks in
      guard var track = tracks[identifier],
        let index = track.frames.firstIndex(where: { $0.sequence == sequence })
      else { return }
      track.append(.deliveryVirtualDevice, at: nanoseconds, toFrameAt: index)
      tracks[identifier] = track
    }
  }

  /// Adds the endpoint delivery to the newest frame of `identifier`.
  public func endpointDelivered(for identifier: LogicalControllerID, at nanoseconds: UInt64) {
    tracks.withLock { tracks in
      guard var track = tracks[identifier], !track.frames.isEmpty else { return }
      track.append(.deliveryEndpoint, at: nanoseconds, toFrameAt: track.frames.count - 1)
      tracks[identifier] = track
    }
  }

  /// The frames of `identifier`, oldest first.
  public func frames(for identifier: LogicalControllerID) -> [FrameTiming] {
    tracks.withLock { $0[identifier]?.frames ?? [] }
  }

  /// Forgets `identifier` once its pipeline stops.
  func forget(_ identifier: LogicalControllerID) {
    tracks.withLock { _ = $0.removeValue(forKey: identifier) }
  }
}
