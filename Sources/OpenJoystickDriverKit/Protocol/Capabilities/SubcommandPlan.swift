/// A family's subcommand reports (`defaults.session.subcommands` in its protocol description):
/// the report id, the rule of the rolling packet counter that every output report of the family
/// shares, the requests sent in order at startup and the player-indicator subcommand. A record
/// never carries one.
struct SubcommandPlan: Equatable, Sendable {
  static let counterModulusRange = 2...256
  static let requestsRange = 1...16

  /// The id of the output report that carries a subcommand.
  let reportID: UInt8
  /// The counter starts at 0 and the one after `n` is `(n + 1) % counterModulus`.
  let counterModulus: Int
  /// The requests of a startup, in send order.
  let requests: [SubcommandRequest]
  /// The subcommand that lights the player indicator.
  let playerIndicator: PlayerIndicatorSubcommand

  init(
    reportID: UInt8,
    counterModulus: Int,
    requests: [SubcommandRequest],
    playerIndicator: PlayerIndicatorSubcommand
  ) throws(ControllerRecordProblem) {
    guard Self.counterModulusRange.contains(counterModulus) else {
      throw ControllerRecordProblem("a subcommand counterModulus is 2...256")
    }
    guard Self.requestsRange.contains(requests.count) else {
      throw ControllerRecordProblem("subcommands name 1...16 requests")
    }
    let purposes = requests.compactMap { $0.spiRead?.purpose }
    guard Set(purposes).count == purposes.count else {
      throw ControllerRecordProblem("each SPI read purpose appears at most once")
    }
    self.reportID = reportID
    self.counterModulus = counterModulus
    self.requests = requests
    self.playerIndicator = playerIndicator
  }

  /// The counter value that follows `counter`.
  func nextCounter(after counter: UInt8) -> UInt8 {
    UInt8(truncatingIfNeeded: (Int(counter) + 1) % counterModulus)
  }

  /// The request that reads for `purpose`, if any.
  func spiRead(for purpose: SubcommandRequest.SPIRead.Purpose) -> SubcommandRequest? {
    requests.first { $0.spiRead?.purpose == purpose }
  }
}

/// The player-indicator subcommand: its id and the one data byte that lights each player.
struct PlayerIndicatorSubcommand: Equatable, Sendable {
  let subcommand: UInt8
  let patterns: [PhysicalPlayerIndicator: UInt8]

  /// Fails unless every indicator has a pattern.
  init(
    subcommand: UInt8,
    patterns: [PhysicalPlayerIndicator: UInt8]
  ) throws(ControllerRecordProblem) {
    guard Set(patterns.keys) == Set(PhysicalPlayerIndicator.allCases) else {
      throw ControllerRecordProblem("a player indicator names a pattern for every indicator")
    }
    self.subcommand = subcommand
    self.patterns = patterns
  }

  /// The data byte that lights `indicator`.
  func pattern(for indicator: PhysicalPlayerIndicator) -> UInt8 {
    guard let pattern = patterns[indicator] else {
      preconditionFailure("a player indicator names a pattern for every indicator")
    }
    return pattern
  }
}

/// One subcommand: its id and either fixed data bytes or an SPI flash read.
struct SubcommandRequest: Equatable, Sendable {
  /// A read of the controller's SPI flash: the address goes out as four little-endian bytes and
  /// then the length.
  struct SPIRead: Equatable, Sendable {
    enum Purpose: String, Equatable, Sendable {
      case factoryMotionCalibration = "FactoryMotionCalibration"
      case userMotionCalibration = "UserMotionCalibration"
    }

    static let lengthRange = 1...29

    let address: UInt32
    let length: UInt8
    let purpose: Purpose
  }

  static let dataRange = 1...16

  let subcommand: UInt8
  let data: [UInt8]
  let spiRead: SPIRead?

  init(subcommand: UInt8, data: [UInt8]) throws(ControllerRecordProblem) {
    guard Self.dataRange.contains(data.count) else {
      throw ControllerRecordProblem("a subcommand request names 1...16 data bytes")
    }
    self.subcommand = subcommand
    self.data = data
    spiRead = nil
  }

  init(subcommand: UInt8, spiRead: SPIRead) throws(ControllerRecordProblem) {
    guard SPIRead.lengthRange.contains(Int(spiRead.length)) else {
      throw ControllerRecordProblem("an SPI read length is 1...29")
    }
    self.subcommand = subcommand
    data =
      (0..<4).map { UInt8(truncatingIfNeeded: spiRead.address >> (8 * UInt32($0))) }
      + [spiRead.length]
    self.spiRead = spiRead
  }
}
