import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordSetTests {
  /// A bundled `xbox.gip` record with no protocol options.
  private static let bundledGIP = ControllerModelID(vendorID: 0x366C, productID: 0x0005)
  /// A bundled `sony.dualshock4` record, a HID family.
  private static let bundledHID = ControllerModelID(vendorID: 0x2C22, productID: 0x2000)
  private static let unbundled = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  private static func patch(_ identity: ControllerModelID, set: [String: Any]) throws -> Data {
    try json([
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordSet.overrideKind,
      "operation": "patch", "vendorID": Int(identity.vendorID),
      "productID": Int(identity.productID), "set": set,
    ])
  }

  private static func add(_ identity: ControllerModelID, family: String) throws -> Data {
    try json([
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordSet.overrideKind,
      "operation": "add",
      "record": [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": Int(identity.vendorID),
        "productID": Int(identity.productID), "protocol": ["family": family],
      ],
    ])
  }

  private static func problem(_ data: Data) -> String? {
    do {
      _ = try ControllerRecordSet.validate(data)
      return nil
    } catch { return ControllerRecordSet.problemDescription(error) }
  }

  @Test
  func patchReplacesOnlyItsFieldsAndMarksThemUser() throws {
    let validated = try ControllerRecordSet.validate(
      Self.patch(Self.bundledGIP, set: ["protocol": ["family": "xbox.gip", "keepAlive": false]])
    )
    #expect(validated.operation == .patch)
    #expect(validated.fileName == "366c-0005.json")
    #expect(validated.record.fieldLayers == ["protocol": .user])
    #expect(validated.record.profile.gipKeepAlivePolicy == .disabled)
    #expect(validated.record.usesRawUSB)
    let bundled = try #require(ControllerRecordSet.bundled.records[Self.bundledGIP])
    #expect(bundled.layer == .bundled)
    #expect(bundled.fieldLayers == ["protocol": .bundled])
  }

  /// A same-family protocol patch keeps the bundled quirks it does not name; a family change
  /// replaces the block, because every protocol field belongs to its family.
  @Test
  func protocolPatchKeepsUnnamedFieldsOnlyWithinTheFamily() throws {
    let shareOffsetGIP = ControllerModelID(vendorID: 0x045E, productID: 0x0B12)
    let kept = try ControllerRecordSet.validate(
      Self.patch(shareOffsetGIP, set: ["protocol": ["family": "xbox.gip", "keepAlive": false]])
    )
    #expect(kept.record.profile.quirks == [.shareOffset])
    #expect(kept.record.profile.gipKeepAlivePolicy == .disabled)
    let refamilied = try ControllerRecordSet.validate(
      Self.patch(Self.bundledHID, set: ["protocol": ["family": "hid.descriptor"]])
    )
    #expect(refamilied.record.profile.physicalProtocolID == .hidDescriptor)
  }

  /// A same-family patch adds its quirks to the bundled quirks instead of replacing them.
  @Test
  func protocolPatchAddsItsQuirksToTheBundledQuirks() throws {
    let dualShock4 = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)
    let patched = try ControllerRecordSet.validate(
      Self.patch(
        dualShock4,
        set: ["protocol": ["family": "sony.dualshock4", "quirks": ["strikepad"]]]
      )
    )
    #expect(patched.record.profile.quirks == [.factoryCalibration, .strikePad])
  }

  @Test
  func tuningPatchSetsTheRecordTuning() throws {
    let validated = try ControllerRecordSet.validate(
      Self.patch(Self.bundledHID, set: ["tuning": ["inputLivenessTimeoutMs": 2_500]])
    )
    #expect(validated.record.fieldLayers["tuning"] == .user)
    #expect(
      validated.record.profile.tuning == ControllerTuning(inputLivenessTimeoutMilliseconds: 2_500)
    )
  }

  @Test
  func addForANewIdentityIsAUserRecord() throws {
    let validated = try ControllerRecordSet.validate(Self.add(Self.unbundled, family: "xbox.gip"))
    #expect(validated.operation == .add)
    #expect(validated.record.model == Self.unbundled)
    #expect(validated.record.fieldLayers == ["protocol": .user])
    #expect(validated.record.family == "xbox.gip")
  }

  @Test
  func recordsThatDoNotFitTheCatalogAreRejected() throws {
    #expect(
      Self.problem(try Self.add(Self.bundledGIP, family: "xbox.gip"))
        == "366C:0005 is a bundled controller; use a patch to change it"
    )
    #expect(
      Self.problem(try Self.patch(Self.unbundled, set: ["protocol": ["family": "xbox.gip"]]))
        == "1234:ABCD is not a bundled controller; use an add record"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["protocol": ["family": "xbox.gip"]]))
        == "the patch changes nothing in the bundled record"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledHID, set: ["usb": ["postHandshakeSettleMs": 5]]))
        == "USB overrides require a raw-USB protocol family"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["capabilities": ["rumble": "absent"]]))
        == "set must hold protocol, usb, bluetoothLE, ownership, output, input, or tuning"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["tuning": ["hidStartupIntervalMs": 5]]))
        == "record.tuning: HID startup and output timings apply only to HID controllers"
    )
    #expect(Self.problem(Data("[]".utf8)) == "the file is not a JSON object")
    let unknownKey = try Self.json([
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordSet.overrideKind,
      "operation": "patch", "vendorID": 0x366C, "productID": 5,
      "set": ["usb": ["postHandshakeSettleMs": 5]], "note": "x",
    ])
    #expect(Self.problem(unknownKey) == "unknown field(s): note")
    let badFamily = try Self.add(Self.unbundled, family: "xbox.unknown")
    #expect(Self.problem(badFamily) == "record.protocol: unknown family xbox.unknown")
  }

  /// A file declares its version through `apiVersion` and its type through `kind`. A missing or
  /// unsupported version, or a kind that is not the one it is read as, is rejected and named.
  @Test
  func aMissingOrUnsupportedHeaderIsRejected() throws {
    let supported = "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    let old = "openjoystickdriver.io/v1beta1"
    let override: [String: Any] = [
      "operation": "patch", "vendorID": 0x366C, "productID": 5,
      "set": ["usb": ["postHandshakeSettleMs": 5]],
    ]
    let noVersion = override.merging(["kind": ControllerRecordSet.overrideKind]) { $1 }
    #expect(Self.problem(try Self.json(noVersion)) == "no apiVersion found; \(supported)")
    let oldVersion = noVersion.merging(["apiVersion": old]) { $1 }
    #expect(
      Self.problem(try Self.json(oldVersion)) == "apiVersion \(old) is not supported; \(supported)"
    )
    let noKind = override.merging(["apiVersion": OpenJoystickDriverAPI.version]) { $1 }
    #expect(
      Self.problem(try Self.json(noKind))
        == "no kind found; expected \(ControllerRecordSet.overrideKind)"
    )
    let wrongKind = noKind.merging(["kind": ControllerRecordDocument.kind]) { $1 }
    #expect(
      Self.problem(try Self.json(wrongKind))
        == "expected \(ControllerRecordSet.overrideKind), found \(ControllerRecordDocument.kind)"
    )
    let oldRecord = try Self.json([
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordSet.overrideKind,
      "operation": "add",
      "record": [
        "apiVersion": old, "kind": ControllerRecordDocument.kind, "vendorID": 0x1234,
        "productID": 0xABCD, "protocol": ["family": "xbox.gip"],
      ],
    ])
    #expect(Self.problem(oldRecord)?.contains("apiVersion \(old) is not supported") == true)
    let oldDefaults = Data(
      #"{"apiVersion": "\#(old)", "kind": "\#(ControllerDefaults.kind)", "tuning": {}}"#.utf8
    )
    #expect(throws: ControllerRecordProblem.self) { try ControllerDefaults.validate(oldDefaults) }
    let defaultsWrongKind = Data(
      #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Persona", "tuning": {}}"#.utf8
    )
    #expect(throws: ControllerRecordProblem.self) {
      try ControllerDefaults.validate(defaultsWrongKind)
    }
  }

  @Test
  func loadAppliesValidFilesAndReportsTheRest() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Self.add(Self.unbundled, family: "xbox.gip").write(
      to: directory.appendingPathComponent("1234-abcd.json")
    )
    try Self.patch(Self.bundledGIP, set: ["usb": ["postHandshakeSettleMs": 5]]).write(
      to: directory.appendingPathComponent("wrong-name.json")
    )
    try Data("{".utf8).write(to: directory.appendingPathComponent("broken.json"))

    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(
      set.userFiles.map(\.url.lastPathComponent) == [
        "1234-abcd.json", "broken.json", "wrong-name.json",
      ]
    )
    #expect(set.records[Self.unbundled]?.layer == .user)
    #expect(set.records[Self.bundledGIP]?.layer == .bundled)
    #expect(set.problems.map(\.url.lastPathComponent) == ["broken.json", "wrong-name.json"])
    #expect(set.problems.last?.problem == "the file name must be 366c-0005.json")
    #expect(set.records.count == ControllerRecordSet.bundled.records.count + 1)

    let catalog = DeviceCatalog(records: set)
    let unit = LogicalControllerID(vendorID: 0x1234, productID: 0xABCD, serialNumber: "S")
    #expect(catalog.record(for: unit.model)?.physicalProtocolID == .xboxGIP)
    #expect(
      catalog.rawUSBModels.contains(
        ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
      )
    )
  }

  /// The stored-file rule: OJD does not migrate a stored file. A file it can read keeps working;
  /// a file it cannot read is dropped, reported with its reason, and left as it was.
  @Test
  func aStoredFileKeepsWorkingOrIsDroppedUnchanged() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-stored-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // A patch as written before `ControllerModelID`: the model is its vendorID and productID.
    let current = Data(
      (#"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","#
        + #""kind":"\#(ControllerRecordSet.overrideKind)","operation":"patch","vendorID":13932,"#
        + #""productID":5,"set":{"protocol":{"family":"xbox.gip","keepAlive":false}}}"#).utf8
    )
    let currentURL = directory.appendingPathComponent("366c-0005.json")
    try current.write(to: currentURL)
    // An add in the `openjoystickdriver.io/v1beta1` schema.
    let released = Data(
      (#"{"apiVersion":"openjoystickdriver.io/v1beta1","#
        + #""kind":"\#(ControllerRecordSet.overrideKind)","operation":"add","record":{"#
        + #""apiVersion":"\#(OpenJoystickDriverAPI.version)","#
        + #""kind":"\#(ControllerRecordDocument.kind)","vendorID":4660,"productID":43981,"#
        + #""protocol":{"family":"xbox.gip"}}}"#).utf8
    )
    let releasedURL = directory.appendingPathComponent("1234-abcd.json")
    try released.write(to: releasedURL)

    let set = ControllerRecordSet.load(userDirectory: directory)

    let kept = try #require(set.records[ControllerModelID(vendorID: 0x366C, productID: 0x0005)])
    #expect(kept.fieldLayers["protocol"] == .user)
    #expect(kept.profile.gipKeepAlivePolicy == .disabled)
    #expect(set.records[Self.unbundled] == nil)
    #expect(set.problems.map(\.url.lastPathComponent) == ["1234-abcd.json"])
    #expect(
      set.problems.first?.problem
        == "1234-abcd.json: apiVersion openjoystickdriver.io/v1beta1 is not supported; "
        + "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    )
    #expect(try Data(contentsOf: releasedURL) == released)
    #expect(try Data(contentsOf: currentURL) == current)
  }

  @Test
  func aMissingDirectoryHoldsNoRecords() {
    let set = ControllerRecordSet.load(
      userDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    )
    #expect(set.userFiles.isEmpty)
    #expect(set.records.count == ControllerRecordSet.bundled.records.count)
  }

  @Test
  func loadIgnoresFilesThatAreNotJSON() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("notes".utf8).write(to: directory.appendingPathComponent("README.txt"))
    try Data("{".utf8).write(to: directory.appendingPathComponent("1234-abcd.json.bak"))

    #expect(ControllerRecordSet.load(userDirectory: directory).userFiles.isEmpty)
  }

  @Test
  func anUnreadableDirectoryIsReportedAndKeepsTheBundledRecords() throws {
    // A regular file stands in for a directory that cannot be listed.
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-records-\(UUID().uuidString)"
    )
    try Data().write(to: path)
    defer { try? FileManager.default.removeItem(at: path) }

    let set = ControllerRecordSet.load(userDirectory: path)
    #expect(set.problems.map(\.url) == [path])
    #expect(set.problems.first?.problem?.hasPrefix("cannot read the directory: ") == true)
    #expect(set.records.count == ControllerRecordSet.bundled.records.count)
  }

  @Test
  func activatingTheSameRecordsChangesNothing() {
    #expect(ControllerRecordSet.bundled.activate().isEmpty)
  }
}
