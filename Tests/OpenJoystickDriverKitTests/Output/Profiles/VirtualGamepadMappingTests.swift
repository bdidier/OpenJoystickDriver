import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualGamepadMappingTests {
  @Test
  func theGenericPersonaUsesTheCRCLessGUIDAndThePublishedButtonUsages() throws {
    let mapping = try VirtualHIDProfileID.generic.gamepadMapping()
    #expect(mapping.guid == "03000000091200004f4a000008040000")
    #expect(
      mapping.sdlMapping
        == "03000000091200004f4a000008040000,OpenJoystickDriver Generic HID Gamepad,"
        + "a:b0,b:b1,x:b2,y:b3,back:b6,guide:b14,start:b7,leftstick:b8,rightstick:b9,"
        + "leftshoulder:b4,rightshoulder:b5,dpup:b10,dpdown:b11,dpleft:b12,dpright:b13,misc1:b15,"
        + "leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:+a4,righttrigger:+a5,"
        + "platform:Mac OS X,"
    )
  }

  @Test
  func theSDLCompatiblePersonaReadsTheDpadAsAHat() throws {
    let mapping = try VirtualHIDProfileID.sdlCompatible.gamepadMapping()
    #expect(mapping.guid == "050000005e040000fd02000000000000")
    #expect(mapping.sdlMapping.contains("dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,"))
    #expect(mapping.sdlMapping.contains("lefttrigger:+a2,righttrigger:+a5,"))
    #expect(mapping.unmapped.isEmpty)
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func theW3CDescriptionFollowsTheCrosswalk(id: VirtualHIDProfileID) throws {
    let mapping = try id.gamepadMapping()
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/Vocabulary/crosswalk.json")
    let root = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    let controls = try #require(root["controls"] as? [String: [String: Any]])
    var buttons: [Int: String] = [:]
    var axes: [Int: String] = [:]
    for (name, entry) in controls {
      if let index = entry["w3cButton"] as? Int { buttons[index] = name }
      if let index = entry["w3cAxis"] as? Int { axes[index] = name }
    }
    #expect(
      mapping.w3cButtons.allSatisfy { buttons[$0.index] == $0.control.rawValue },
      "\(mapping.w3cButtons)"
    )
    #expect(
      mapping.w3cAxes.allSatisfy { axes[$0.index] == $0.control.rawValue },
      "\(mapping.w3cAxes)"
    )
    #expect(mapping.w3cAxes.count == 4)
    #expect(mapping.w3cButtons.map(\.index) == mapping.w3cButtons.map(\.index).sorted())
  }
}
