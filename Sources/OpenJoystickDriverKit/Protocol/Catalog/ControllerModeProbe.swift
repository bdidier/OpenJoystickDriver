import Foundation
import IOKit

/// A read-only behavioral probe: one read of a feature report whose answer, stall, or byte pattern
/// tells a mode apart. A probe has no write; ``ControllerModeProbeReader`` offers none either.
public struct ControllerModeProbe: Equatable, Sendable {
  /// What the read must show for the probe to hold.
  public enum Expectation: Equatable, Sendable {
    /// The device answers the read.
    case answers
    /// The device refuses the read.
    case stalls
    /// The reply holds `expected` starting at `offset`.
    case bytes(offset: Int, expected: [UInt8])
  }

  /// What one reply says about a probe.
  public enum Verdict: Equatable, Sendable {
    case satisfied
    case unsatisfied
    /// The device gave no usable reply, so the probe says nothing either way.
    case inconclusive
  }

  public let reportID: UInt8
  public let length: Int
  public let expectation: Expectation

  public init(reportID: UInt8, length: Int, expectation: Expectation) {
    self.reportID = reportID
    self.length = length
    self.expectation = expectation
  }

  var request: PhysicalHIDFeatureReadRequest {
    PhysicalHIDFeatureReadRequest(reportID: reportID, length: length)
  }

  /// A timeout, a device that stopped responding, or an unavailable route proves nothing; any
  /// other IOKit refusal is the device declining the read, which is a stall.
  func verdict(for result: PhysicalHIDReportResult<Data>) -> Verdict {
    switch result {
    case .success(let data):
      switch expectation {
      case .answers: return .satisfied
      case .stalls: return .unsatisfied
      case .bytes(let offset, let expected):
        let reply = [UInt8](data)
        guard reply.count >= offset + expected.count else { return .unsatisfied }
        return Array(reply[offset..<offset + expected.count]) == expected
          ? .satisfied : .unsatisfied
      }
    case .unavailable:
      return .inconclusive
    case .failed(.ioReturn(let code)):
      if code == kIOReturnTimeout || code == kIOReturnNotResponding { return .inconclusive }
      return expectation == .stalls ? .satisfied : .unsatisfied
    }
  }
}

/// The only access a probe has to a controller: a feature-report read. There is no write
/// requirement, so a probe cannot change a controller.
public protocol ControllerModeProbeReader: Sendable {
  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
}
