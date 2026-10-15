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
    try json(ControllerPatch.document(selector: .identity(identity), body: set))
  }

  private static func add(_ identity: ControllerModelID, family: String) throws -> Data {
    try json([
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(identity.vendorID),
      "productID": Int(identity.productID),
      "modes": [["id": "default", "protocol": ["family": family]]],
    ])
  }

  private static func problem(_ data: Data) -> String? {
    do {
      _ = try ControllerRecordSet.validate(data)
      return nil
    } catch { return ControllerRecordSet.problemDescription(error) }
  }

  private static func record(_ data: Data) throws -> ControllerRecord {
    try #require(try ControllerRecordSet.validate(data).record)
  }

  private static func problemCode(_ data: Data) -> ErrorCode? {
    do {
      _ = try ControllerRecordSet.validate(data)
      return nil
    } catch { return ControllerRecordSet.problemCode(error) }
  }

  @Test
  func patchReplacesOnlyItsFieldsAndMarksThemUser() throws {
    let validated = try ControllerRecordSet.validate(
      Self.patch(
        Self.bundledGIP,
        set: [
          "modes": [["id": "default", "protocol": ["family": "xbox.gip", "keepAlive": false]]]
        ]
      )
    )
    let record = try #require(validated.record)
    #expect(validated.operation == .patch)
    #expect(validated.fileName == "366c-0005.patch.json")
    #expect(record.fieldLayers == ["modes": .user])
    #expect(record.profile.gipKeepAlivePolicy == .disabled)
    #expect(record.usesRawUSB)
    let bundled = try #require(ControllerRecordSet.bundled.records[Self.bundledGIP])
    #expect(bundled.layer == .bundled)
    #expect(bundled.fieldLayers == ["modes": .bundled])
  }

  /// A patch replaces `modes` as an array, so a restated default mode keeps only the parameters it
  /// names.
  @Test
  func modesPatchReplacesTheDefaultModeWholesale() throws {
    let shareOffsetGIP = ControllerModelID(vendorID: 0x045E, productID: 0x0B12)
    let bundledShare = try #require(ControllerRecordSet.bundled.records[shareOffsetGIP])
    #expect(bundledShare.profile.parameters == ProtocolParameters(shareButton: .init(fromEnd: 26)))
    let replaced = try Self.record(
      Self.patch(
        shareOffsetGIP,
        set: [
          "modes": [["id": "default", "protocol": ["family": "xbox.gip", "keepAlive": false]]]
        ]
      )
    )
    #expect(replaced.profile.parameters == ProtocolParameters())
    #expect(replaced.profile.gipKeepAlivePolicy == .disabled)
    let refamilied = try Self.record(
      Self.patch(
        Self.bundledHID,
        set: ["modes": [["id": "default", "protocol": ["family": "hid.descriptor"]]]]
      )
    )
    #expect(refamilied.profile.physicalProtocolID == .hidDescriptor)
  }

  /// A same-family patch adds its parameters to the bundled parameters instead of replacing them.
  @Test
  func modesPatchReplacesTheBundledParameters() throws {
    let dualShock4 = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)
    let patched = try Self.record(
      Self.patch(
        dualShock4,
        set: [
          "modes": [
            [
              "id": "default",
              "protocol": [
                "family": "sony.dualshock4", "parameters": ["motionScale": "StrikePad"],
              ],
            ]
          ]
        ]
      )
    )
    #expect(patched.profile.parameters == ProtocolParameters(motionScale: .strikePad))
  }

  @Test
  func tuningPatchSetsTheRecordTuning() throws {
    let record = try Self.record(
      Self.patch(Self.bundledHID, set: ["tuning": ["inputLivenessTimeoutMs": 2_500]])
    )
    #expect(record.fieldLayers["tuning"] == .user)
    #expect(record.profile.tuning == ControllerTuning(inputLivenessTimeoutMilliseconds: 2_500))
  }

  @Test
  func aControllerFileForANewIdentityIsAUserRecord() throws {
    let validated = try ControllerRecordSet.validate(Self.add(Self.unbundled, family: "xbox.gip"))
    let record = try #require(validated.record)
    #expect(validated.operation == .add)
    #expect(validated.fileName == "1234-abcd.json")
    #expect(record.model == Self.unbundled)
    #expect(record.fieldLayers == ["modes": .user])
    #expect(record.family == "xbox.gip")
  }

  @Test
  func recordsThatDoNotFitTheCatalogAreRejected() throws {
    #expect(
      Self.problem(try Self.add(Self.bundledGIP, family: "xbox.gip"))
        == "366C:0005 is a bundled controller; use a patch to change it"
    )
    #expect(
      Self.problem(
        try Self.patch(
          Self.unbundled,
          set: ["modes": [["id": "default", "protocol": ["family": "xbox.gip"]]]]
        )
      )
        == "1234:ABCD is not a known controller; use a Controller file"
    )
    #expect(
      Self.problem(
        try Self.patch(
          Self.bundledGIP,
          set: ["modes": [["id": "default", "protocol": ["family": "xbox.gip"]]]]
        )
      )
        == "the patch changes nothing in the record"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledHID, set: ["usb": ["postHandshakeSettleMs": 5]]))
        == "USB overrides require a raw-USB protocol family"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["capabilities": ["rumble": "absent"]]))
        == "patch must hold modes, usb, bluetoothLE, server, "
        + "route, output, input, or tuning"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["tuning": ["hidStartupIntervalMs": 5]]))
        == "record.tuning: HID startup and output timings apply only to HID controllers"
    )
    #expect(Self.problem(Data("[]".utf8)) == "the file is not a JSON object")
    var withNote = ControllerPatch.document(
      selector: .identity(Self.bundledGIP),
      body: ["usb": ["postHandshakeSettleMs": 5]]
    )
    withNote["note"] = "x"
    #expect(
      Self.problem(try Self.json(withNote))
        == "the file must hold exactly apiVersion, kind, selector, and patch"
    )
    let badFamily = try Self.add(Self.unbundled, family: "xbox.unknown")
    #expect(Self.problem(badFamily) == "record.modes.[0].protocol: unknown family xbox.unknown")
  }

  /// A file declares its version through `apiVersion` and its type through `kind`. A missing or
  /// unsupported version, or a kind that is not one it is read as, is rejected and named. The
  /// removed `ControllerOverride` and `ControllerDefaults` kinds are wrong kinds like any other.
  @Test
  func aMissingOrUnsupportedHeaderIsRejected() throws {
    let supported = "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    let old = "openjoystickdriver.io/v1beta1"
    let body = ControllerPatch.document(
      selector: .identity(Self.bundledGIP),
      body: ["usb": ["postHandshakeSettleMs": 5]]
    )
    let noVersion = body.filter { $0.key != "apiVersion" }
    #expect(
      Self.problem(try Self.json(noVersion)) == "E5001: no apiVersion found; \(supported)"
    )
    #expect(Self.problemCode(try Self.json(noVersion)) == .unsupportedAPIVersion)
    let oldVersion = body.merging(["apiVersion": old]) { $1 }
    #expect(
      Self.problem(try Self.json(oldVersion))
        == "E5001: apiVersion \(old) is not supported; \(supported)"
    )
    #expect(Self.problemCode(try Self.json(oldVersion)) == .unsupportedAPIVersion)
    let noKind = body.filter { $0.key != "kind" }
    #expect(
      Self.problem(try Self.json(noKind)) == "no kind found; expected \(ControllerPatch.kind)"
    )
    for removed in ["ControllerOverride", "ControllerDefaults", "Persona"] {
      let wrongKind = body.merging(["kind": removed]) { $1 }
      #expect(
        Self.problem(try Self.json(wrongKind))
          == "expected \(ControllerPatch.kind), found \(removed)"
      )
    }
    let oldRecord = try Self.json([
      "apiVersion": old, "kind": ControllerRecordDocument.kind, "vendorID": 0x1234,
      "productID": 0xABCD, "modes": [["id": "default", "protocol": ["family": "xbox.gip"]]],
    ])
    #expect(Self.problem(oldRecord)?.contains("apiVersion \(old) is not supported") == true)
    #expect(Self.problemCode(oldRecord) == .unsupportedAPIVersion)
    let oldDefaults = try Self.json(
      ControllerPatch.document(selector: .all, body: ["tuning": ["stickDeadzone": 0.1]])
        .merging(["apiVersion": old]) { $1 }
    )
    do {
      _ = try ControllerDefaults.validate(oldDefaults)
      Issue.record("the old defaults were accepted")
    } catch { #expect(ControllerRecordSet.problemCode(error) == .unsupportedAPIVersion) }
    let defaultsWrongKind = Data(
      #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Persona", "tuning": {}}"#.utf8
    )
    do {
      _ = try ControllerDefaults.validate(defaultsWrongKind)
      Issue.record("the wrong kind was accepted")
    } catch { #expect(ControllerRecordSet.problemCode(error) == nil) }
  }

  @Test
  func loadAppliesValidFilesAndReportsTheRest() throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
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
    #expect(set.problems.last?.problem == "the file name must be 366c-0005.patch.json")
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
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-stored-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let current = Data(
      (#"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","#
        + #""kind":"ControllerPatch","selector":{"vendorID":13932,"productID":5},"#
        + #""patch":{"modes":[{"id":"default","#
        + #""protocol":{"family":"xbox.gip","keepAlive":false}}]}}"#).utf8
    )
    let currentURL = directory.appendingPathComponent("366c-0005.patch.json")
    try current.write(to: currentURL)
    // A Controller file in the `openjoystickdriver.io/v1beta1` schema.
    let released = Data(
      (#"{"apiVersion":"openjoystickdriver.io/v1beta1","#
        + #""kind":"\#(ControllerRecordDocument.kind)","vendorID":4660,"productID":43981,"#
        + #""modes":[{"id":"default","protocol":{"family":"xbox.gip"}}]}"#).utf8
    )
    let releasedURL = directory.appendingPathComponent("1234-abcd.json")
    try released.write(to: releasedURL)
    // A file of the removed `ControllerOverride` kind.
    let removed = Data(
      (#"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"ControllerOverride","#
        + #""operation":"patch","vendorID":13932,"productID":5,"set":{"usb":{}}}"#).utf8
    )
    let removedURL = directory.appendingPathComponent("366c-0005.json")
    try removed.write(to: removedURL)

    let set = ControllerRecordSet.load(userDirectory: directory)

    let kept = try #require(set.records[ControllerModelID(vendorID: 0x366C, productID: 0x0005)])
    #expect(kept.fieldLayers["modes"] == .user)
    #expect(kept.profile.gipKeepAlivePolicy == .disabled)
    #expect(set.records[Self.unbundled] == nil)
    #expect(set.problems.map(\.url.lastPathComponent) == ["1234-abcd.json", "366c-0005.json"])
    #expect(
      set.problems.first?.problem
        == "E5001: 1234-abcd.json: apiVersion openjoystickdriver.io/v1beta1 is not supported; "
        + "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    )
    #expect(
      set.problems.last?.problem
        == "366c-0005.json: expected ControllerPatch, found ControllerOverride"
    )
    #expect(try Data(contentsOf: releasedURL) == released)
    #expect(try Data(contentsOf: currentURL) == current)
    #expect(try Data(contentsOf: removedURL) == removed)
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
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
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
    let path = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
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
