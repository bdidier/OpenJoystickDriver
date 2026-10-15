import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The GIP named startup packets come from `defaults.session.namedPackets` in the
/// family's description. The decoder accepts and rejects the documents the Python validator does
/// (the protocol description tests); the bytes the driver sends are pinned in
/// `GIPStartupPacketBytesTests`.
struct NamedPacketDescriptionTests {
  private static let powerOn =
    #"{"id": "xbox.gip/power-on", "bytes": [5, 32, 0, 1, 0], "sessionByte": 2}"#

  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", "endpoints": {"in": 130, "out": 2}, \(body)}
      """
    return try ProtocolDescription.decode(
      Data(json.utf8),
      protocolID: family,
      fileName: "\(family.rawValue).json"
    )
  }

  private func rejects(family: PhysicalProtocolID = .xboxGIP, _ packets: String) -> Bool {
    do {
      _ = try decode(family: family, #""defaults": {"session": {"namedPackets": \#(packets)}}"#)
      return false
    } catch { return true }
  }

  private func packet(
    id: String = "xbox.gip/power-on",
    bytes: String = "[5, 32, 0, 1, 0]",
    members: String = #""sessionByte": 2"#
  ) -> String {
    #"{"id": "\#(id)", "bytes": \#(bytes), \#(members)}"#
  }

  @Test
  func acceptsWellFormedPackets() throws {
    let ledOn = packet(id: "xbox.gip/led-on", bytes: "[10, 32, 0]")
    let description = try decode(
      family: .xboxGIP,
      #""defaults": {"session": {"namedPackets": [\#(Self.powerOn), \#(ledOn)]}}"#
    )
    let plan = try #require(description.namedPackets)
    #expect(plan.packets.map(\.id) == ["xbox.gip/power-on", "xbox.gip/led-on"])
    #expect(plan.packet(named: "xbox.gip/power-on")?.write.bytes == [5, 32, 0, 1, 0])
    #expect(plan.packet(named: "xbox.gip/power-on")?.write.sessionByte == 2)
    #expect(plan.packet(named: "xbox.gip/missing") == nil)
  }

  @Test
  func rejectsMalformedPackets() {
    let sixteen = (0..<16).map { packet(id: "xbox.gip/packet-\($0)") }
    let seventeen = (0..<17).map { packet(id: "xbox.gip/packet-\($0)") }
    #expect(!rejects("[\(sixteen.joined(separator: ","))]"))
    for packets in [
      "[]",
      "[\(seventeen.joined(separator: ","))]",
      #"[{"bytes": [5, 32, 0], "sessionByte": 2}]"#,
      #"[{"id": "xbox.gip/power-on", "sessionByte": 2}]"#,
      #"[{"id": "xbox.gip/power-on", "bytes": [5, 32, 0]}]"#,
      "[\(packet(id: "power-on"))]",
      "[\(packet(id: "xbox.gip/Power-On"))]",
      "[\(packet(id: "xbox.gip/power--on"))]",
      "[\(packet(id: "xbox.gip/"))]",
      "[\(packet(bytes: "[5, 32]"))]",
      "[\(packet(bytes: "[5, 32, 256]"))]",
      "[\(packet(members: #""sessionByte": 1"#))]",
      "[\(packet(members: #""sessionByte": 3"#))]",
      "[\(packet(members: #""sessionByte": 2, "endpoint": 2"#))]",
      "[\(Self.powerOn), \(packet(bytes: "[5, 32, 0, 2]"))]",
      "[\(packet(id: "xbox.xusb/power-on"))]",
    ] {
      #expect(rejects(packets), "\(packets)")
    }
  }

  @Test
  func onlyGIPHasNamedPackets() {
    for family in [PhysicalProtocolID.sonyDualSense, .xboxXUSB, .xboxXID, .nintendoSwitch2] {
      #expect(rejects(family: family, "[\(Self.powerOn)]"), "\(family.rawValue)")
    }
  }

  private func decodeStartup(
    _ startup: String,
    packets: Bool = true
  ) throws
    -> ProtocolDescription
  {
    let session = packets ? #""session": {"namedPackets": [\#(Self.powerOn)]}, "# : ""
    return try decode(
      family: .xboxGIP,
      #""defaults": {\#(session)"output": {"startup": \#(startup)}}"#
    )
  }

  @Test
  func startupReferencesNamedPacketsWithTheirBytes() throws {
    let description = try decodeStartup(
      #"[{"packet": "xbox.gip/power-on"}, {"packet": "xbox.gip/power-on", "variants": ["usb"]}]"#
    )
    #expect(description.usbStartupWrites.map(\.bytes) == [[5, 32, 0, 1, 0], [5, 32, 0, 1, 0]])
    #expect(description.usbStartupWrites.allSatisfy { $0.sessionByte == 2 })
    #expect(description.usbStartupWrites[0].condition == .always)
    #expect(description.usbStartupWrites[1].condition != .always)
  }

  @Test
  func startupRejectsWhatItCannotResolveOrMix() {
    let usb = #"{"bytes": [1, 2, 3]}"#
    let reference = #"{"packet": "xbox.gip/power-on"}"#
    for startup in [
      #"[{"packet": "xbox.gip/missing"}]"#,
      #"[{"packet": "xbox.gip/power-on", "bytes": [1, 2, 3]}]"#,
      #"[{"packet": 7}]"#,
      "[\(reference), \(usb)]",
      "[\(usb), \(reference)]",
    ] {
      #expect((try? decodeStartup(startup)) == nil, "\(startup)")
    }
    #expect((try? decodeStartup("[\(reference)]", packets: false)) == nil)
  }

  @Test
  func aRecordCannotReferToAPacketInItsStartup() {
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(
        ControllerRecordDocument.Output.self,
        from: Data(#"{"startup": [{"packet": "xbox.gip/power-on"}]}"#.utf8)
      )
    }
  }

  @Test
  func theBundledGIPStartupIsTheThreeReferencedPackets() throws {
    let description = PhysicalProtocolID.xboxGIP.protocolDescription
    let plan = try #require(description.namedPackets)
    let expected = ["power-on", "led-on", "auth-done"].compactMap {
      plan.packet(named: "xbox.gip/\($0)")?.write
    }
    #expect(expected.count == 3)
    #expect(description.usbStartupWrites == expected)
  }

  @Test
  func theBundledGIPDescriptionHoldsTheEightPackets() throws {
    let plan = try #require(PhysicalProtocolID.xboxGIP.protocolDescription.namedPackets)
    #expect(
      plan.packets.map(\.id) == [
        "xbox.gip/power-on", "xbox.gip/s-init", "xbox.gip/enable-extra-input",
        "xbox.gip/hori-ack", "xbox.gip/led-on", "xbox.gip/auth-done", "xbox.gip/rumble-begin",
        "xbox.gip/rumble-end",
      ]
    )
    #expect(plan.packets.allSatisfy { $0.write.sessionByte == 2 })
  }
}
