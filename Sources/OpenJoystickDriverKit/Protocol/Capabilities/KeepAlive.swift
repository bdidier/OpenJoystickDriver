/// A family's keep-alive (`defaults.session.keepAlive` in its protocol description): how often the
/// driver's keep-alive runs, and the fixed packets each run sends. A mode's `session.keepAlive`
/// declares one for a raw-USB family whose description declares none.
struct KeepAlive: Equatable, Sendable {
  static let intervalRange = 1...60_000
  static let writesRange = 1...8

  /// The period of the keep-alive, in milliseconds.
  let intervalMilliseconds: Int
  /// The fixed writes of each run; a driver adds the writes that change with its state, such as
  /// a running rumble. Empty for a family whose whole keep-alive is state.
  let writes: [KeepAliveWrite]

  init(
    intervalMilliseconds: Int,
    writes: [KeepAliveWrite] = []
  ) throws(ControllerRecordProblem) {
    guard Self.intervalRange.contains(intervalMilliseconds) else {
      throw ControllerRecordProblem("a keep-alive interval is 1...60000 ms")
    }
    guard writes.isEmpty || Self.writesRange.contains(writes.count) else {
      throw ControllerRecordProblem("keepAlive names no writes or 1...8 of them")
    }
    self.intervalMilliseconds = intervalMilliseconds
    self.writes = writes
  }
}

/// One fixed keep-alive write. It has the startup write's formats, a HID report or a raw-USB
/// packet, without startup's phase, delay, transport, CRC seed, tolerance and `when`, which only
/// a startup sequence uses.
struct KeepAliveWrite: Equatable, Sendable {
  enum Payload: Equatable, Sendable {
    case hid(RecordStartupWrite)
    case usb(USBStartupWrite)

    var condition: StartupWriteCondition {
      switch self {
      case .hid(let write): write.condition
      case .usb(let write): write.condition
      }
    }
  }

  let payload: Payload
  /// The tuning key whose value is the number of runs between sends of this write; nil sends it
  /// on every run. Only `lizardResendTicks` is one.
  let resendTuning: ControllerTuning.Key?

  static let resendTuningKeys: Set<ControllerTuning.Key> = [.lizardResendTicks]

  /// Whether run number `tick` (counted from 0) sends this write, given the value of its
  /// `resendTuning` key.
  func isDue(tick: Int, resendTicks: Int) -> Bool {
    resendTuning == nil || tick.isMultiple(of: resendTicks)
  }

  /// The packet or report this write sends. `session` stamps a raw-USB write's session byte.
  func output(
    defaultEndpoint: UInt8,
    defaultTimeoutMilliseconds: Int,
    session: ((_ bytes: [UInt8]) -> UInt8)? = nil
  ) -> PhysicalOutputWrite {
    switch payload {
    case .hid(let write): write.write
    case .usb(let write):
      write.write(
        defaultEndpoint: defaultEndpoint,
        defaultTimeoutMilliseconds: defaultTimeoutMilliseconds,
        session: session
      )
    }
  }
}
