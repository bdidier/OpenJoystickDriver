import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A reader that answers each report from a table and counts its reads. It implements only the
/// read, like every ``ControllerModeProbeReader``.
private final class ScriptedProbeReader: ControllerModeProbeReader {
  private let replies: [UInt8: PhysicalHIDReportResult<Data>]
  private let reads = Locked<[UInt8]>([])

  init(_ replies: [UInt8: PhysicalHIDReportResult<Data>]) { self.replies = replies }

  var readReports: [UInt8] { reads.withLock { $0 } }

  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    reads.withLock { $0.append(request.reportID) }
    return replies[request.reportID] ?? .unavailable
  }
}

private let stall = PhysicalHIDReportResult<Data>.failed(
  .ioReturn(IOReturn(bitPattern: 0xE000_404F))
)
private let timeout = PhysicalHIDReportResult<Data>.failed(.ioReturn(kIOReturnTimeout))

struct ControllerModeTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  /// A model whose default mode is `hid.descriptor` with two alternatives, each with one probe.
  private static var twoModes: [[String: Any]] {
    [
      mode(
        "dualshock",
        family: "sony.dualshock4",
        probe: ["report": 160, "length": 8, "expect": "answers"]
      ),
      mode(
        "dualsense",
        family: "sony.dualsense",
        probe: ["report": 161, "length": 8, "expect": "bytes", "offset": 1, "bytes": "0A FF"]
      ),
    ]
  }

  private static func mode(
    _ id: String,
    family: String,
    probe: [String: Any]
  ) -> [String: Any] {
    ["id": id, "protocol": ["family": family], "match": ["probes": [probe]]]
  }

  private static func profile(
    modes: [[String: Any]]?,
    family: String = "hid.descriptor"
  ) throws
    -> DeviceRuntimeProfile
  {
    var record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID),
      "protocol": ["family": family],
    ]
    record["modes"] = modes
    let data = try JSONSerialization.data(withJSONObject: record)
    return try #require(try ControllerRecordSet.validate(data).record).profile
  }

  private static func select(
    _ profile: DeviceRuntimeProfile,
    reader: ScriptedProbeReader,
    log: Locked<[String]> = Locked([])
  ) async -> ControllerModeSelection {
    await ControllerModeSelector.select(
      from: profile,
      model: model,
      backend: .ioHID,
      reader: reader
    ) { line in log.withLock { $0.append(line) } }
  }

  @Test
  func aRecordWithTwoModesPicksEachByItsProbe() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let answered = Data([0x00, 0x0A, 0xFF, 0x00])

    let first = await Self.select(profile, reader: ScriptedProbeReader([160: .success(answered)]))
    #expect(first == .matched("dualshock"))
    #expect(profile.applying(modeID: first.modeID)?.physicalProtocolID == .sonyDualShock4)

    let second = await Self.select(
      profile,
      reader: ScriptedProbeReader([160: stall, 161: .success(answered)])
    )
    #expect(second == .matched("dualsense"))
    #expect(profile.applying(modeID: second.modeID)?.physicalProtocolID == .sonyDualSense)
    #expect(profile.applying(modeID: second.modeID)?.modeID == "dualsense")
  }

  @Test
  func differentProbeRepliesChooseEachRecordOfOneVendorAndProduct() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let wrongBytes = Data([0x00, 0x0B, 0xFF, 0x00])
    let shortReply = Data([0x00])
    let cases: [(String, [UInt8: PhysicalHIDReportResult<Data>], ControllerModeSelection)] = [
      ("first mode answers", [160: .success(Data([1]))], .matched("dualshock")),
      (
        "second mode's bytes match", [160: stall, 161: .success(Data([0, 0x0A, 0xFF]))],
        .matched("dualsense")
      ),
      ("bytes differ", [160: stall, 161: .success(wrongBytes)], .noModeMatched),
      ("reply too short for the pattern", [160: stall, 161: .success(shortReply)], .noModeMatched),
      ("nothing answers but both refuse", [160: stall, 161: stall], .noModeMatched),
    ]
    for (name, replies, expected) in cases {
      let selection = await Self.select(profile, reader: ScriptedProbeReader(replies))
      #expect(selection == expected, Comment(rawValue: name))
    }
    // The record the runtime binds is the default one unless a mode was selected.
    #expect(profile.applying(modeID: nil)?.physicalProtocolID == .hidDescriptor)
    #expect(profile.applying(modeID: "missing") == nil)
  }

  @Test
  func aModeRequiresEveryProbeAndReadsEachReportOnce() async throws {
    let profile = try Self.profile(modes: [
      [
        "id": "both",
        "protocol": ["family": "sony.dualshock4"],
        "match": [
          "probes": [
            ["report": 160, "length": 8, "expect": "answers"],
            ["report": 160, "length": 8, "expect": "bytes", "offset": 0, "bytes": "01"],
          ]
        ],
      ]
    ])
    let reader = ScriptedProbeReader([160: .success(Data([1, 2]))])
    #expect(await Self.select(profile, reader: reader) == .matched("both"))
    #expect(reader.readReports == [160])
  }

  @Test
  func aProbeWithoutAReplyFallsBackToTheDefaultModeAndLogsIt() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let replies: [(String, PhysicalHIDReportResult<Data>)] = [
      ("timeout", timeout),
      ("unavailable", .unavailable),
      ("not responding", .failed(.ioReturn(kIOReturnNotResponding))),
    ]
    for (name, reply) in replies {
      let log = Locked<[String]>([])
      let selection = await Self.select(
        profile,
        reader: ScriptedProbeReader([160: reply, 161: .success(Data([0, 0x0A, 0xFF]))]),
        log: log
      )
      // The second mode's probe would hold, but a probe that said nothing ends the selection.
      #expect(selection == .probeInconclusive(reportID: 160), Comment(rawValue: name))
      #expect(selection.modeID == nil)
      let lines = log.withLock { $0 }
      #expect(lines.count == 1)
      #expect(lines.first?.contains("1234:ABCD") == true)
      #expect(lines.first?.contains("report=160") == true)
      #expect(lines.first?.contains("default mode") == true)
      // The controller stays enabled: its default profile still binds.
      #expect(profile.applying(modeID: selection.modeID)?.physicalProtocolID == .hidDescriptor)
    }
  }

  @Test
  func aStallSatisfiesAStallsProbeAndAnAnswerSatisfiesItNot() async throws {
    let profile = try Self.profile(modes: [
      Self.mode(
        "quiet",
        family: "sony.dualshock4",
        probe: ["report": 5, "length": 4, "expect": "stalls"]
      )
    ])
    #expect(
      await Self.select(profile, reader: ScriptedProbeReader([5: stall])) == .matched("quiet")
    )
    #expect(
      await Self.select(profile, reader: ScriptedProbeReader([5: .success(Data([5]))]))
        == .noModeMatched
    )
  }

  @Test
  func aStallWhereAnAnswerIsExpectedFallsBackToTheDefaultMode() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let log = Locked<[String]>([])
    let selection = await Self.select(
      profile,
      reader: ScriptedProbeReader([160: stall, 161: stall]),
      log: log
    )
    #expect(selection == .noModeMatched)
    #expect(selection.modeID == nil)
    #expect(log.withLock { $0 }.last?.contains("default mode") == true)
    #expect(profile.applying(modeID: selection.modeID)?.physicalProtocolID == .hidDescriptor)
  }

  @Test
  func onlyTheDevicesOwnRefusalIsAStall() async throws {
    let profile = try Self.profile(modes: [
      Self.mode(
        "quiet",
        family: "sony.dualshock4",
        probe: ["report": 5, "length": 4, "expect": "stalls"]
      )
    ])
    let unsupported = PhysicalHIDReportResult<Data>.failed(.ioReturn(kIOReturnUnsupported))
    #expect(
      await Self.select(profile, reader: ScriptedProbeReader([5: unsupported])) == .matched("quiet")
    )
    let notTheDevices: [IOReturn] = [
      kIOReturnNotOpen, kIOReturnNoDevice, kIOReturnAborted, kIOReturnNotPermitted,
      kIOReturnExclusiveAccess, kIOReturnError,
    ]
    for code in notTheDevices {
      let log = Locked<[String]>([])
      let selection = await Self.select(
        profile,
        reader: ScriptedProbeReader([5: .failed(.ioReturn(code))]),
        log: log
      )
      #expect(selection == .probeInconclusive(reportID: 5), "\(code)")
      #expect(log.withLock { $0 }.count == 1)
    }
  }

  @Test
  func aDeviceOffTheIOHIDRouteIsNotProbed() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let reader = ScriptedProbeReader([160: .success(Data([1]))])
    let log = Locked<[String]>([])
    let selection = await ControllerModeSelector.select(
      from: profile,
      model: Self.model,
      backend: .coreBluetoothGATT,
      reader: reader
    ) { line in log.withLock { $0.append(line) } }
    #expect(selection == .noProbeRoute)
    #expect(selection.modeID == nil)
    #expect(reader.readReports.isEmpty)
    #expect(log.withLock { $0 }.first?.contains("coreBluetoothGATT") == true)
  }

  @Test
  func aReadThatNeverReturnsGivesUpAtTheDeadline() async {
    let release = DispatchSemaphore(value: 0)
    let started = ContinuousClock.now
    let result = await BoundedHIDRead.run(timeout: 0.05) {
      release.wait()
      return .success(Data([1]))
    }
    release.signal()
    guard case .failed(.ioReturn(let code)) = result else {
      Issue.record("expected a timeout")
      return
    }
    #expect(code == kIOReturnTimeout)
    #expect(ContinuousClock.now - started < .seconds(5))
    // A read inside the deadline keeps its own answer, and a timeout is no stall.
    let fast = await BoundedHIDRead.run(timeout: 5) { .success(Data([7])) }
    guard case .success(let data) = fast else {
      Issue.record("expected the answer")
      return
    }
    #expect(data == Data([7]))
    #expect(
      ControllerModeProbe(reportID: 1, length: 1, expectation: .stalls).verdict(for: result)
        == .inconclusive
    )
  }

  @Test
  func aRecordWithoutModesReadsNothing() async throws {
    let profile = try Self.profile(modes: nil)
    let reader = ScriptedProbeReader([:])
    #expect(await Self.select(profile, reader: reader) == .noModes)
    #expect(reader.readReports.isEmpty)
    #expect(profile.modes.isEmpty)
  }

  @Test
  func theDualShock3EFProbeIsDecodedFromTheBundledRecord() async throws {
    let ds3 = ControllerModelID(vendorID: 0x054C, productID: 0x0268)
    let profile = try #require(ControllerRecordSet.bundled.records[ds3]?.profile)
    let mode = try #require(profile.modes.first)
    #expect(profile.modes.count == 1)
    #expect(mode.probes == [ControllerModeProbe(reportID: 0xEF, length: 49, expectation: .answers)])
    #expect(mode.physicalProtocolID == .sonySixaxis)

    let answering = await ControllerModeSelector.select(
      from: profile,
      model: ds3,
      backend: .ioHID,
      reader: ScriptedProbeReader([0xEF: .success(Data(repeating: 0, count: 49))])
    ) { _ in }
    #expect(answering == .matched(mode.id))
    let stalling = await ControllerModeSelector.select(
      from: profile,
      model: ds3,
      backend: .ioHID,
      reader: ScriptedProbeReader([0xEF: stall])
    ) { _ in }
    #expect(stalling == .noModeMatched)
    #expect(stalling.modeID == nil)
  }

  @Test
  func recordsWithoutModesAreUnchangedByTheirAbsence() throws {
    let record = try #require(
      ControllerRecordSet.bundled.records.values.first { $0.profile.modes.isEmpty }
    )
    #expect(record.profile.applying(modeID: nil) == record.profile)
  }

  @Test
  func aUserPatchMayReplaceTheModes() throws {
    let patch = try JSONSerialization.data(
      withJSONObject: ControllerPatch.document(
        selector: .identity(ControllerModelID(vendorID: 0x2C22, productID: 0x2000)),
        body: ["modes": Self.twoModes]
      )
    )
    let patched = try #require(try ControllerRecordSet.validate(patch).record).profile
    #expect(patched.modes.map(\.id) == ["dualshock", "dualsense"])
  }

  @Test
  func invalidModesAreRejected() throws {
    let probe: [String: Any] = ["report": 160, "length": 8, "expect": "answers"]
    func mode(
      _ id: String,
      family: String = "sony.dualshock4",
      probe: [String: Any] = probe
    )
      -> [String: Any]
    { Self.mode(id, family: family, probe: probe) }
    let rejected: [(String, [[String: Any]]?, String)] = [
      ("empty", [], "hid.descriptor"),
      ("duplicate ID", [mode("a"), mode("a")], "hid.descriptor"),
      ("reserved ID", [mode("default")], "hid.descriptor"),
      ("uppercase ID", [mode("Mode")], "hid.descriptor"),
      ("ID with a trailing newline", [mode("abc\n")], "hid.descriptor"),
      (
        "bytes with a trailing newline",
        [
          mode(
            "a",
            probe: ["report": 1, "length": 8, "expect": "bytes", "offset": 0, "bytes": "AB\n"]
          )
        ], "hid.descriptor"
      ),
      ("raw-USB mode", [mode("a", family: "xbox.gip")], "hid.descriptor"),
      ("raw-USB default", [mode("a")], "xbox.gip"),
      (
        "unknown write key", [mode("a", probe: probe.merging(["write": "01"]) { $1 })],
        "hid.descriptor"
      ),
      (
        "lowercase hex",
        [
          mode(
            "a",
            probe: ["report": 1, "length": 8, "expect": "bytes", "offset": 0, "bytes": "ab"]
          )
        ], "hid.descriptor"
      ),
      (
        "bytes past length",
        [
          mode(
            "a",
            probe: ["report": 1, "length": 2, "expect": "bytes", "offset": 1, "bytes": "01 02"]
          )
        ], "hid.descriptor"
      ),
      (
        "offset on answers", [mode("a", probe: probe.merging(["offset": 0]) { $1 })],
        "hid.descriptor"
      ),
      (
        "report above 255", [mode("a", probe: probe.merging(["report": 256]) { $1 })],
        "hid.descriptor"
      ),
    ]
    for (name, modes, family) in rejected {
      #expect(throws: (any Error).self, Comment(rawValue: name)) {
        _ = try Self.profile(modes: modes, family: family)
      }
    }
  }
}
