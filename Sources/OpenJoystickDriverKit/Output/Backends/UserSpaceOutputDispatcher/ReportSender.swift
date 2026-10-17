import Foundation

/// One bounded, ordered stream for event reports and host-protocol replies.
///
/// At most `queueCapacity` submissions wait behind the one being sent. When the queue is full, a
/// new submission evicts the oldest waiting frame (newest wins); the evicted frame's receipt fails
/// with ``Failure/superseded``. Every frame carries the complete controller state, so the newest
/// frame still brings the virtual device up to date. A submission that is not a frame, such as a
/// host output report, is never evicted: with no frame left to evict it fails with
/// ``Failure/queueOverflow``, while a frame that finds only such submissions fails with
/// ``Failure/superseded``.
/// Closing revokes new submissions and detaches the backend before the active native send drains.
final class UserSpaceReportSender: Sendable {
  enum Failure: Error, Equatable, LocalizedError, Sendable {
    case queueOverflow
    case sendTimedOut
    /// A newer frame took the place of this one in a full queue.
    case superseded

    var errorDescription: String? {
      switch self {
      case .queueOverflow: "Virtual controller publication queue overflowed."
      case .sendTimedOut: "Virtual controller publication timed out."
      case .superseded: "Virtual controller frame superseded by a newer frame."
      }
    }
  }

  /// Matches the virtual output transition deadline used to retire native virtual devices.
  static let defaultNativeSendDeadlineNanoseconds: UInt64 = 2_000_000_000

  final class SubmissionReceipt: Sendable {
    private struct State: Sendable {
      var result: Result<Void, any Error>?
      var waiters: [CheckedContinuation<Void, any Error>] = []
    }

    private let state = Locked(State())

    func finish(_ result: Result<Void, any Error>) {
      let waiters = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
        guard state.result == nil else { return [] }
        state.result = result
        defer { state.waiters.removeAll() }
        return state.waiters
      }
      for waiter in waiters { waiter.resume(with: result) }
    }

    func value() async throws {
      try await withCheckedThrowingContinuation { continuation in
        let result = state.withLock { state -> Result<Void, any Error>? in
          if let result = state.result { return result }
          state.waiters.append(continuation)
          return nil
        }
        if let result { continuation.resume(with: result) }
      }
    }
  }

  /// Races one native send against its deadline and resumes the waiting publisher exactly once.
  ///
  /// The send runs in an unstructured task and the deadline on a timer, not in a task group,
  /// because a group awaits every child: a native send that ignores cancellation would hold the
  /// worker past the deadline. Cancelling the waiting publisher (closing) must also not cut the
  /// deadline short, so the send can still drain until then.
  private final class NativeSendOperation: Sendable {
    private struct State: Sendable {
      var completed = false
      var cancellationRequested = false
      var sendTask: Task<Void, Never>?
      var cancelDeadline: DeadlineTimer.Cancel?
      var continuation: CheckedContinuation<Void, any Error>?
    }

    private let state = Locked(State())

    func start(
      report: [UInt8],
      backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend,
      deadlineNanoseconds: UInt64,
      timer: DeadlineTimer,
      continuation: CheckedContinuation<Void, any Error>
    ) {
      state.withLock { $0.continuation = continuation }
      let send = Task.detached { [weak self] in
        do {
          try await backend.send(report)
          self?.finish(.success(()))
        } catch { self?.finish(.failure(error)) }
      }
      // The deadline runs on a timer thread of its own, not the cooperative pool, so a starved
      // pool cannot delay it.
      let cancelDeadline = timer.schedule(deadlineNanoseconds) { [weak self] in
        if self?.isCancellationRequested() == true {
          self?.finish(.failure(CancellationError()))
        } else {
          backend.close()
          self?.finish(.failure(Failure.sendTimedOut))
        }
      }
      let didComplete = state.withLock { state -> Bool in
        state.sendTask = send
        state.cancelDeadline = cancelDeadline
        return state.completed
      }
      if didComplete {
        send.cancel()
        cancelDeadline()
      }
    }

    func cancel() {
      let sendTask = state.withLock { state -> Task<Void, Never>? in
        state.cancellationRequested = true
        return state.sendTask
      }
      sendTask?.cancel()
    }

    private func isCancellationRequested() -> Bool { state.withLock { $0.cancellationRequested } }

    private func finish(_ result: Result<Void, any Error>) {
      let (continuation, cancelDeadline) = state.withLock {
        state -> (CheckedContinuation<Void, any Error>?, DeadlineTimer.Cancel?) in
        guard !state.completed else { return (nil, nil) }
        state.completed = true
        defer { state.continuation = nil }
        return (state.continuation, state.cancelDeadline)
      }
      cancelDeadline?()
      continuation?.resume(with: result)
    }
  }

  private struct Submission: Sendable {
    let completion: SubmissionReceipt
    /// Whether a newer frame may take this submission's place in a full queue.
    let isFrame: Bool
    let whileActive: @Sendable () -> Bool
    let requireActive: Bool
    let reports: @Sendable () throws -> [[UInt8]]
  }

  private struct State: Sendable {
    var backend: (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?
    var worker: Task<Void, Never>?
    var pending: [ObjectIdentifier: SubmissionReceipt] = [:]
    /// The submissions waiting for the worker, oldest first; never longer than the capacity.
    var queue: [Submission] = []
    var active: SubmissionReceipt?
    var closeTask: Task<Void, Never>?
    var closed = false
  }

  private let state = Locked(State())
  /// Wakes the worker; one pending wake covers every submission queued before it runs.
  private let continuation: AsyncStream<Void>.Continuation
  private let nativeSendDeadlineNanoseconds: UInt64
  private let deadlineTimer: DeadlineTimer
  private let queueCapacity: Int

  /// The number of submissions waiting behind the one being sent.
  var queuedCount: Int { state.withLock { $0.queue.count } }

  init(
    nativeSendDeadlineNanoseconds: UInt64 = defaultNativeSendDeadlineNanoseconds,
    queueCapacity: Int = ControllerTuning.defaultFrameQueueCapacity,
    deadlineTimer: DeadlineTimer = .dispatch
  ) {
    // Decoding refuses a capacity outside the range, so another value is a programming error.
    precondition(
      ControllerTuning.frameQueueCapacityRange.contains(queueCapacity),
      "frame queue capacity \(queueCapacity) is outside \(ControllerTuning.frameQueueCapacityRange)"
    )
    self.nativeSendDeadlineNanoseconds = nativeSendDeadlineNanoseconds
    self.deadlineTimer = deadlineTimer
    self.queueCapacity = queueCapacity
    let (wakes, continuation) = AsyncStream.makeStream(
      of: Void.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    self.continuation = continuation
    let worker = Task { [weak self] in
      for await _ in wakes {
        while let self, let submission = self.dequeue() { await self.publish(submission) }
      }
    }
    state.withLock { $0.worker = worker }
  }

  deinit { _ = beginClose() }

  func attach(_ backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend) {
    let rejected = state.withLock { state in
      guard !state.closed, state.backend == nil else { return true }
      state.backend = backend
      return false
    }
    if rejected { backend.close() }
  }

  private func dequeue() -> Submission? {
    state.withLock { $0.queue.isEmpty ? nil : $0.queue.removeFirst() }
  }

  /// Builds reports in the retained worker only after preceding publication completes.
  ///
  /// Enqueueing stays synchronous: IOKit's set-report callback acknowledges ordered enqueueing
  /// and cannot await. Await `SubmissionReceipt.value()` for the publication outcome. A submission
  /// with `isFrame` may be superseded by a newer one when the queue is full.
  func submit(
    isFrame: Bool = false,
    whileActive: @escaping @Sendable () -> Bool = { true },
    requireActive: Bool = false,
    _ reports: @escaping @Sendable () throws -> [[UInt8]]
  ) -> SubmissionReceipt {
    let completion = SubmissionReceipt()
    let submission = Submission(
      completion: completion,
      isFrame: isFrame,
      whileActive: whileActive,
      requireActive: requireActive,
      reports: reports
    )
    let (result, superseded) = state.withLock {
      state -> (Result<Void, any Error>?, SubmissionReceipt?) in
      guard !state.closed else { return (.failure(CancellationError()), nil) }
      var superseded: SubmissionReceipt?
      if state.queue.count >= queueCapacity {
        guard let index = state.queue.firstIndex(where: \.isFrame) else {
          // The waiting host replies go first, so a frame that finds only replies is the
          // older state and yields to the next frame.
          return (.failure(isFrame ? Failure.superseded : Failure.queueOverflow), nil)
        }
        let evicted = state.queue.remove(at: index).completion
        state.pending.removeValue(forKey: ObjectIdentifier(evicted))
        superseded = evicted
      }
      state.pending[ObjectIdentifier(completion)] = completion
      state.queue.append(submission)
      return (nil, superseded)
    }
    superseded?.finish(.failure(Failure.superseded))
    if let result {
      completion.finish(result)
    } else {
      continuation.yield(())
    }
    return completion
  }

  private func publish(_ submission: Submission) async {
    state.withLock { $0.active = submission.completion }
    defer {
      state.withLock { state in
        state.pending.removeValue(forKey: ObjectIdentifier(submission.completion))
        if state.active === submission.completion { state.active = nil }
      }
    }
    do {
      try Task.checkCancellation()
      let backend = try state.withLock { state in
        guard !state.closed, let backend = state.backend else { throw CancellationError() }
        return backend
      }
      for report in try submission.reports() {
        guard !state.withLock({ $0.closed }) else { throw CancellationError() }
        guard submission.whileActive() else {
          if submission.requireActive { throw CancellationError() }
          submission.completion.finish(.success(()))
          return
        }
        try await send(report, to: backend)
      }
      submission.completion.finish(.success(()))
    } catch { submission.completion.finish(.failure(error)) }
  }

  private func send(
    _ report: [UInt8],
    to backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend
  ) async throws {
    let operation = NativeSendOperation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        operation.start(
          report: report,
          backend: backend,
          deadlineNanoseconds: nativeSendDeadlineNanoseconds,
          timer: deadlineTimer,
          continuation: continuation
        )
      }
    } onCancel: {
      operation.cancel()
    }
  }

  @discardableResult
  func beginClose() -> Task<Void, Never> {
    let result = state.withLock {
      state -> (
        Task<Void, Never>, (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?,
        [SubmissionReceipt]
      ) in
      if let closeTask = state.closeTask { return (closeTask, nil, []) }
      state.closed = true
      continuation.finish()
      state.queue.removeAll()
      let backend = state.backend
      state.backend = nil
      let activeIdentifier = state.active.map { ObjectIdentifier($0) }
      let cancellations = state.pending.compactMap { key, completion in
        key == activeIdentifier ? nil : completion
      }
      state.pending.removeAll()
      state.worker?.cancel()
      let worker = state.worker
      let task = Task {
        // The backend is closed right after this task starts; wait until the native device is
        // gone, so a replacement is never published beside it.
        await backend?.waitUntilClosed()
        if let worker { await worker.value }
      }
      state.closeTask = task
      return (task, backend, cancellations)
    }
    result.1?.close()
    result.2.forEach { $0.finish(.failure(CancellationError())) }
    return result.0
  }
}
