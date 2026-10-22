import Foundation
import OpenJoystickDriverKit

/// How long a timed capture runs, as the `--duration` of `ojd controller capture` and
/// `ojd record draft`: a number of seconds above 0.
enum CaptureDuration {
  /// The duration the sheet starts with, as `ojd record draft`.
  static let defaultSeconds = 10.0

  /// The seconds `text` names in `locale`, or nil when it is not a finite number above 0.
  static func parse(_ text: String, locale: Locale = .current) -> Double? {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    guard let number = formatter.number(from: text.trimmingCharacters(in: .whitespaces)) else {
      return nil
    }
    let seconds = number.doubleValue
    return seconds.isFinite && seconds > 0 ? seconds : nil
  }

  /// The text the field starts with.
  static func text(for seconds: Double, locale: Locale = .current) -> String {
    return seconds.formatted(.number.locale(locale).precision(.fractionLength(0...3)))
  }
}

/// Collects the packets a controller sends and receives during a span of time, as
/// `ojd controller capture --duration` and `ojd record draft` do.
enum ControllerPacketCapture {
  /// The pause between reads of the packet log, the CLI's polling interval.
  static let pollIntervalNanoseconds: UInt64 = 16_000_000

  /// The packets that arrive after the call, read from `read` every ``pollIntervalNanoseconds``
  /// until `seconds` have passed on `uptime`. Throws when a read fails or the task is cancelled.
  static func collect(
    seconds: Double,
    read: @Sendable () async throws -> [PacketLogEntry],
    uptime: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
  ) async throws -> [PacketLogEntry] {
    var cursor = PacketLogSnapshotCursor(snapshot: try await read())
    let start = uptime()
    let limit = UInt64(seconds * 1_000_000_000)
    var packets: [PacketLogEntry] = []
    while uptime() - start < limit {
      packets += cursor.consume(snapshot: try await read())
      try await sleep(pollIntervalNanoseconds)
    }
    return packets
  }

  /// The packets of `device`, read from `gateway`.
  static func collect(
    from device: ApplicationServiceDeviceDescription,
    gateway: any ControllerDiagnosticsGateway,
    seconds: Double
  ) async throws -> [PacketLogEntry] {
    let selector = ControllerReference.session(device.sessionToken)
    return try await collect(seconds: seconds) { try await gateway.packetLog(for: selector) }
  }

  /// The captured packets as the JSON the Developer tools export.
  static func exportData(_ packets: [PacketLogEntry]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(packets)
  }

  /// The suggested file name of a capture of `device`.
  static func fileName(for device: ApplicationServiceDeviceDescription) -> String {
    String(
      format: "OpenJoystickDriver-packets-%04X-%04X.json",
      device.vendorID,
      device.productID
    )
  }
}

/// Drafts a controller record from a capture, as `ojd record draft` does.
enum ControllerRecordDrafting {
  struct NoLayout: Error, Equatable {
    let identity: String

    var message: String {
      OJDLocalized.formatted("ui.controllers.draftRecord.noLayout", identity)
    }
  }

  /// The report descriptor of the controller model, read from the system.
  static func physicalDescriptor(for device: ApplicationServiceDeviceDescription) -> [UInt8]? {
    HIDDescriptorReportFormat.copyPhysicalReportDescriptor(
      vendorID: Int(device.vendorID),
      productID: Int(device.productID)
    )
  }

  /// The record drafted from the input reports among `packets` and the controller's HID report
  /// `descriptor`. Throws ``NoLayout`` when no control could be read and the model's bundled
  /// record already names its family.
  static func draft(
    for device: ApplicationServiceDeviceDescription,
    packets: [PacketLogEntry],
    descriptor: [UInt8]?
  ) throws -> ControllerRecordDraft {
    let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    guard
      let draft = ControllerRecordDraft(
        model: model,
        bundled: ControllerRecordSet.bundled.records[model] != nil,
        descriptor: descriptor,
        reports: packets.filter { $0.direction == .received }.map(\.reportBytes)
      )
    else { throw NoLayout(identity: model.description) }
    return draft
  }

  /// The suggested file name of the record, `VVVV-PPPP.json`.
  static func fileName(for device: ApplicationServiceDeviceDescription) -> String {
    String(format: "%04X-%04X.json", device.vendorID, device.productID)
  }
}
