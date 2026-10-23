import Foundation

/// Builds input reports according to a HID report descriptor (subset parser).
///
/// This is used for virtual HID profiles where consumers switch behavior based on VID/PID
/// (often SDL-based). In those cases, spoofing VID/PID alone is not enough: the descriptor and
/// report bytes must match what the consumer expects.
public struct HIDDescriptorReportFormat: VirtualGamepadReportFormat, Sendable {
  public let descriptor: [UInt8]
  public let inputReportPayloadSize: Int
  public let inputReportID: UInt8?
  public let outputReportPayloadSize: Int?
  public let outputReportID: UInt8?

  private let packer: HIDReportPacker

  public enum Error: Swift.Error, CustomStringConvertible, Equatable, Sendable {
    case noSuitableInputReport
    case cannotParseDescriptor

    public var description: String {
      switch self {
      case .noSuitableInputReport:
        return "Descriptor does not contain a usable GamePad-style input report (buttons/axes/hat)."
      case .cannotParseDescriptor: return "Failed to parse HID report descriptor."
      }
    }
  }

  public init(
    descriptor: [UInt8],
    outputReportID: UInt8? = nil,
    outputReportPayloadSize: Int? = nil,
    buttonUsageMap: [Int: Int] = [:],
    digitalUsageMap: [Int: HIDInputUsage] = [:]
  ) throws {
    self.descriptor = descriptor
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: descriptor) else {
      throw Error.cannotParseDescriptor
    }
    guard
      let packer = HIDReportPacker.bestEffortGamepadPacker(
        from: parsed,
        buttonUsageMap: buttonUsageMap,
        digitalUsageMap: digitalUsageMap
      )
    else { throw Error.noSuitableInputReport }
    self.packer = packer
    self.inputReportID = packer.reportID == 0 ? nil : packer.reportID
    self.inputReportPayloadSize = packer.payloadSizeBytes
    self.outputReportID = outputReportID
    self.outputReportPayloadSize = outputReportPayloadSize
  }

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    packer.pack(state: state)
  }
}
