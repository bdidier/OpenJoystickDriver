import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Task 9.1f: the GIP named startup packets come from `defaults.session.namedPackets` in the
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
