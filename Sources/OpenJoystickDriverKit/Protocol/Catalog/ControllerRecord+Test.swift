import Foundation

/// How a replayed capture compares with the state a person expects.
public struct ControllerRecordTestResult: Equatable, Sendable {
  /// One field of the controller state that differs; `expected` and `actual` are its JSON.
  public struct Difference: Equatable, Sendable {
    public let field: String
    public let expected: String
    public let actual: String

    public init(field: String, expected: String, actual: String) {
      self.field = field
      self.expected = expected
      self.actual = actual
    }
  }

  /// How many of the capture's received packets carried input.
  public let inputReports: Int
  /// Empty when the states match.
  public let differences: [Difference]

  public var matches: Bool { differences.isEmpty }

  public init(inputReports: Int, differences: [Difference]) {
    self.inputReports = inputReports
    self.differences = differences
  }
}

/// Why a record test could not compare a capture with an expectation.
public enum ControllerRecordTestError: Error, Equatable, Sendable {
  /// The capture's line (one-based) is not a packet object, or the capture is not UTF-8 text
  /// (line 1).
  case capture(line: Int, problem: String)
  /// The expectation is not a controller state.
  case expectation(problem: String)
  /// The record cannot replay the capture.
  case replay(ControllerRecordReplayError)
}

extension ControllerRecord {
  /// Replays the received packets of `capture` through this record's parser and compares the
  /// resulting state with `expectation`.
  ///
  /// The capture holds one packet JSON object per line, as `ojd controller capture --json` prints
  /// them; a line's time field is not read. The expectation is a controller state as JSON. The
  /// `connection` field is not compared: the service stamps it and no parser sets it.
  public func test(capture: Data, expectation: Data) throws -> ControllerRecordTestResult {
    let reports = try Self.receivedReports(in: capture)
    let expected: ControllerState
    do { expected = try JSONDecoder().decode(ControllerState.self, from: expectation) } catch {
      throw ControllerRecordTestError.expectation(problem: "\(error)")
    }
    let replay: ControllerRecordReplay
    do { replay = try self.replay(reports: reports) } catch let error as ControllerRecordReplayError
    {
      throw ControllerRecordTestError.replay(error)
    }
    return ControllerRecordTestResult(
      inputReports: replay.inputReports,
      differences: try Self.differences(expected: expected, actual: replay.state)
    )
  }

  private struct CaptureLine: Decodable {
    let direction: PacketLogDirection
    let hex: String
    let length: Int

    var bytes: [UInt8] { PacketLogEntry.bytes(hex: hex) }
  }

  private static func receivedReports(in data: Data) throws -> [[UInt8]] {
    guard let text = String(bytes: data, encoding: .utf8) else {
      throw ControllerRecordTestError.capture(line: 1, problem: "not UTF-8 text")
    }
    var reports: [[UInt8]] = []
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (offset, line) in lines.enumerated() where !line.allSatisfy(\.isWhitespace) {
      let entry: CaptureLine
      do { entry = try JSONDecoder().decode(CaptureLine.self, from: Data(line.utf8)) } catch {
        throw ControllerRecordTestError.capture(
          line: offset + 1,
          problem: error.localizedDescription
        )
      }
      guard entry.bytes.count == entry.length else {
        throw ControllerRecordTestError.capture(
          line: offset + 1,
          problem: "length does not match hex"
        )
      }
      if entry.direction == .received { reports.append(entry.bytes) }
    }
    return reports
  }

  private static func differences(
    expected: ControllerState,
    actual: ControllerState
  ) throws -> [ControllerRecordTestResult.Difference] {
    let expectedFields = try fields(expected)
    let actualFields = try fields(actual)
    return expectedFields.keys.sorted().compactMap { field in
      guard field != "connection", expectedFields[field] != actualFields[field] else { return nil }
      return ControllerRecordTestResult.Difference(
        field: field,
        expected: expectedFields[field] ?? "",
        actual: actualFields[field] ?? ""
      )
    }
  }

  /// Each top-level field of the state's JSON, rendered with sorted keys.
  private static func fields(_ state: ControllerState) throws -> [String: String] {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
    return try (object as? [String: Any] ?? [:]).mapValues {
      let data = try JSONSerialization.data(
        withJSONObject: $0,
        options: [.sortedKeys, .fragmentsAllowed]
      )
      return String(bytes: data, encoding: .utf8) ?? ""
    }
  }
}
