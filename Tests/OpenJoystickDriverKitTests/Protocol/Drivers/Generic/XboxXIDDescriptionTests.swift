import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The XboxXID protocol description, run through the generic interpreter beside `XIDDriver`.
/// The recorded samples are the characterization steps for the 20-byte XID report: one neutral
/// report, each digital bit, every D-pad value, analog buttons and triggers at several values, and
/// each stick word at its signed extremes, plus a repeated report and a short one.
struct XboxXIDDescriptionTests {
  private let receivedAt = MonotonicTimestamp(
    nanoseconds: DriverParseCharacterizationTests.receivedAt
  )

  private func interpreter() throws -> ReportLayoutDriver {
    let description = try #require(ProtocolDescription.bundled[.xboxXID])
    return ReportLayoutDriver(layout: try #require(description.inputLayout))
  }

  private func coded() throws -> any PhysicalProtocolDriver {
    try DriverParseCharacterizationTests().driver(
      DriverLifecycleCharacterizationTests.xidGamepad
    )
  }

  private func reports(of steps: [DriverParseCharacterizationTests.Step]) -> [(String, Data)] {
    steps.compactMap {
      if case .report(let data) = $0.input { return ($0.label, data) }
      return nil
    }
  }

  @Test
  func descriptionFramesMatchTheCodedParserOnEveryRecordedSample() throws {
    let codedDriver = try coded()
    let described = try interpreter()
    let samples = reports(of: DriverParseCharacterizationTests.xidSteps)
    #expect(samples.count > 50)
    for (label, data) in samples {
      let expected = try codedDriver.parse(report: data, receivedAt: receivedAt)
      let actual = try described.parse(report: data, receivedAt: receivedAt)
      #expect(actual == expected, "sample \(label)")
    }
  }

  /// Every value of each byte the layout reads, and every stick word, on a neutral report.
  @Test
  func descriptionFramesMatchTheCodedParserAcrossEveryFieldValue() throws {
    let base = [UInt8](repeating: 0, count: 20)
    var reports: [[UInt8]] = []
    for offset in [2, 4, 5, 6, 7, 8, 9, 10, 11] {
      for value in 0...255 {
        var bytes = base
        bytes[offset] = UInt8(value)
        reports.append(bytes)
      }
    }
    for offset in [12, 14, 16, 18] {
      for word in 0...Int(UInt16.max) {
        var bytes = base
        bytes[offset] = UInt8(word & 0xFF)
        bytes[offset + 1] = UInt8(word >> 8)
        reports.append(bytes)
      }
    }
    let codedDriver = try coded()
    let described = try interpreter()
    for bytes in reports {
      let expected = try codedDriver.parse(report: Data(bytes), receivedAt: receivedAt)
      let actual = try described.parse(report: Data(bytes), receivedAt: receivedAt)
      #expect(actual == expected, "report \(bytes)")
    }
  }

  @Test
  func bundledDescriptionDeclaresTheTwentyByteReport() throws {
    let layout = try #require(ProtocolDescription.bundled[.xboxXID]?.inputLayout)
    #expect(layout.reportID == nil)
    #expect(layout.minimumLength == 20)
  }
}
