import Foundation
import OpenJoystickDriverKit

extension EndpointServer {
  /// Runs a `feed` on the connection's thread: opens a virtual gamepad, applies each frame line to
  /// it, and sends the host's rumble commands as lines until either side closes.
  ///
  /// A pump exchanges with the feed each poll to send rumble, but that does not count as activity:
  /// a feed whose client sends no frame line for ``VirtualFeedExchangeResult/idleTimeoutSeconds``
  /// is closed with `E1009`, so a stalled client does not hold a button or a slot. When the feed's
  /// frame queue is full, reading waits, which pushes back on the client.
  /// A client that closes the connection meanwhile ends the feed, though its unread lines wait.
  func feed(_ connection: EndpointConnection, persona: VirtualHIDProfileID) {
    guard let feeds else {
      connection.close(
        EndpointError(code: .feedClosed, message: "The service runs no virtual gamepads.")
      )
      return
    }
    let token: UUID
    do {
      token = try Self.waitFor(connection) {
        try await feeds.open(profile: persona.rawValue, pool: .endpoint).token
      }
    } catch {
      connection.close(Self.feedError(error, persona: persona))
      return
    }
    let exchanger = FeedExchanger(feeds: feeds, token: token, connection: connection)
    let pump = Task {
      while !Task.isCancelled, exchanger.exchange([]) != nil {
        try? await Task.sleep(nanoseconds: ControllerWatchPoller.pollInterval)
      }
    }
    defer {
      pump.cancel()
      Task { await feeds.close(token: token) }
    }
    connection.send(EndpointFeedSession(as: persona))

    while true {
      switch connection.readMessage() {
      case .end: return
      case .tooLong:
        connection.close(Self.invalid("A message is longer than \(Self.maximumLineBytes) bytes."))
        return
      case .invalid(let reason):
        connection.close(Self.invalid(reason))
        return
      case .message(let data):
        let frame: VirtualFeedFrame
        switch Self.frame(data) {
        case .success(let decoded): frame = decoded
        case .failure(let refusal):
          connection.close(refusal)
          return
        }
        while let accepted = exchanger.exchange([frame]), accepted == 0 {
          if connection.peerHungUp { return }
          usleep(useconds_t(VirtualFeedExchangeResult.minimumFrameMilliseconds * 1_000))
        }
        if exchanger.isClosed { return }
      }
    }
  }

  /// The frame on the line, or the error that refuses the line: the header errors of
  /// ``EndpointHeader``, or `E1004` for a `Frame` that does not decode.
  ///
  /// ``VirtualFeedFrame`` takes the envelope as optional for the CLI's stdin lines, so the header
  /// is checked first.
  private static func frame(_ data: Data) -> Result<VirtualFeedFrame, EndpointError> {
    if let refusal = EndpointHeader.refusal(of: data, accepting: [VirtualFeedFrame.kind]) {
      return .failure(refusal)
    }
    guard let frame = try? JSONDecoder().decode(VirtualFeedFrame.self, from: data) else {
      return .failure(invalid("Send Frame lines that match the endpoint schema after FeedSession."))
    }
    return .success(frame)
  }

  private static func feedError(_ error: any Error, persona: VirtualHIDProfileID) -> EndpointError {
    switch error as? VirtualFeedError {
    case .unknownProfile:
      invalid("\(persona.rawValue) is not a persona the service publishes.")
    case .tooManyFeeds(let limit):
      EndpointError(
        code: .tooManyFeeds,
        message: "The service already runs \(limit) virtual gamepads."
      )
    default:
      EndpointError(
        code: .feedClosed,
        message: "The virtual gamepad did not start: \(error.localizedDescription)"
      )
    }
  }

  /// Runs `work` and blocks the calling thread, a connection-queue thread, until it finishes;
  /// cancels `work` once `connection` is closing or its peer hung up.
  private static func waitFor<T: Sendable>(
    _ connection: EndpointConnection,
    _ work: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    let task = Task {
      do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
      done.signal()
    }
    let poll = DispatchTimeInterval.nanoseconds(Int(ControllerWatchPoller.pollInterval))
    while done.wait(timeout: .now() + poll) == .timedOut {
      if connection.isClosing || connection.peerHungUp { task.cancel() }
    }
    return try box.result!.get()
  }
}

/// Written by one task before the semaphore signals, read after it.
/// - Note: `@unchecked Sendable` because the semaphore orders the write before the read.
private final class ResultBox<T>: @unchecked Sendable {
  var result: Result<T, any Error>?
}

/// Exchanges with one feed and sends its rumble lines; the lock keeps the pump's lines and the
/// reader's lines in the order the feed returned them.
///
/// - Note: `@unchecked Sendable` because `closed` is guarded by `lock`.
private final class FeedExchanger: @unchecked Sendable {
  private let feeds: VirtualFeedRegistry
  private let token: UUID
  private weak var connection: EndpointConnection?
  private let lock = NSLock()
  private var closed = false

  init(feeds: VirtualFeedRegistry, token: UUID, connection: EndpointConnection) {
    self.feeds = feeds
    self.token = token
    self.connection = connection
  }

  var isClosed: Bool { lock.withLock { closed } }

  /// Queues `frames` and sends the feedback; returns how many frames the feed accepted, or nil
  /// once the connection is closing, which closes the feed, or the feed closed, which closes the
  /// connection with `E1009`.
  func exchange(_ frames: [VirtualFeedFrame]) -> Int? {
    lock.withLock {
      guard !closed else { return nil }
      guard let connection, !connection.isClosing else {
        // Removes the pad now; the reader may stay blocked until the connection's writer drains.
        closed = true
        Task { [feeds, token] in await feeds.close(token: token) }
        return nil
      }
      let result = feeds.exchange(
        token: token,
        frames: frames,
        countsAsActivity: !frames.isEmpty
      )
      guard !result.closed else {
        closed = true
        connection.close(EndpointError(code: .feedClosed, message: "The virtual gamepad closed."))
        return nil
      }
      for command in result.feedback.compactMap(RumbleCommandLine.init) {
        connection.send(EndpointRumbleCommand(command), bounded: true)
      }
      return result.accepted
    }
  }
}
