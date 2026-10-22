import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Where `ojd record` reads and writes user controller records, and how it reads its input.
enum RecordStore {
  /// The user record directory; tests replace it.
  @TaskLocal
  static var directory = ControllerRecordSet.userDirectory

  /// Reads stdin for the `-` operand; tests replace it.
  @TaskLocal
  static var standardInput: @Sendable () -> Data = {
    FileHandle.standardInput.readDataToEndOfFile()
  }

  static func load() -> ControllerRecordSet { ControllerRecordSet.load(userDirectory: directory) }

  /// The persona files OJD reads, beside the record directory as in the user's support folder.
  static func personaFiles() -> [VirtualPersonaFile] {
    VirtualHIDProfileOverrideStore(
      directory: directory.deletingLastPathComponent()
        .appendingPathComponent("Personas", isDirectory: true)
    ).files
  }

  /// The bytes of `FILE`, or of stdin for `-`.
  static func read(_ path: String) throws -> Data {
    if path == "-" { return standardInput() }
    do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
      throw CLIFailure.usage(
        CLILocalized.format(
          "cli.record.group.errorUnreadable",
          path,
          error.localizedDescription
        )
      )
    }
  }

  /// Prints each skipped user file on stderr.
  static func warn(_ files: [ControllerRecordFile]) {
    for file in files {
      CLIOutput.stderr(
        CLILocalized.format(
          "cli.record.group.skipped",
          file.url.path,
          file.problem ?? ""
        )
      )
    }
  }
}

/// The `VVVV:PPPP` operand of `record show` and `record remove`.
extension ControllerModelID: ExpressibleByArgument {
  public init?(argument: String) {
    guard case .model(let model) = ControllerReference(argument) else { return nil }
    self = model
  }
}

/// How OJD reaches a record's controller. The raw values are stable identifiers.
enum RecordTransport: String, Encodable, Equatable {
  case hid = "HID"
  case usb = "USB"

  init(_ record: ControllerRecord) { self = record.usesRawUSB ? .usb : .hid }
}

/// Whether the signed USB extension can claim a raw-USB controller. Its USB entitlement is a
/// product list Apple signs, so a user record cannot add a product to it.
enum RecordTransportClaim: String, Encodable, Equatable {
  case claimed = "Claimed"
  case unclaimed = "Unclaimed"

  init?(_ record: ControllerRecord) {
    guard let claimed = record.isClaimedByUSBExtension else { return nil }
    self = claimed ? .claimed : .unclaimed
  }
}

/// A user file OJD skipped, and why.
struct SkippedRecord: Encodable, Equatable {
  let file: String
  let problem: String

  init(_ file: ControllerRecordFile) {
    self.file = file.url.path
    problem = file.problem ?? ""
  }

  init(_ file: VirtualPersonaFile) {
    self.file = file.url.path
    problem = file.problem ?? ""
  }

  /// The `all.patch.json` OJD ignored, or nil when it applied the file or the file is absent.
  init?(_ defaults: ControllerDefaults?) {
    guard let defaults, let problem = defaults.problem else { return nil }
    file = defaults.url.path
    self.problem = problem
  }
}

/// One record in `record list --json`.
struct RecordEntry: Encodable, Equatable {
  let identity: String
  let vendorID: Int
  let productID: Int
  let family: String
  let layer: String
  let file: String?

  init(_ record: ControllerRecord) {
    identity = deviceIdentity(
      vendorID: Int(record.model.vendorID),
      productID: Int(record.model.productID)
    )
    vendorID = Int(record.model.vendorID)
    productID = Int(record.model.productID)
    family = record.family
    layer = record.layer.rawValue
    file = record.file?.path
  }
}
