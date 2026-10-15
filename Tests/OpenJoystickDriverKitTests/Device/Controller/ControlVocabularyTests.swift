import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The control vocabulary: the Swift enum, the schema definitions, and the
/// crosswalk to SDL and the system HID names.
struct ControlVocabularyTests {
  @Test
  func anIDOutsideTheVocabularyDoesNotDecode() {
    let data = Data("\"x\(UUID().uuidString)\"".utf8)

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Control.self, from: data)
    }
  }

  @Test
  func everyIDIsUpperCamelCase() {
    for control in Control.allCases {
      let id = control.rawValue
      #expect(id.first?.isUppercase == true, "\(id)")
      #expect(id.allSatisfy { $0.isLetter || $0.isNumber }, "\(id)")
    }
    #expect(Set(Control.allCases.map(\.rawValue)).count == Control.allCases.count)
  }

  @Test
  func schemaDefinitionsMatchTheSwiftCases() throws {
    let definitions = try Self.vocabularyDefinitions()
    func values(_ name: String) -> [String]? {
      (definitions[name] as? [String: Any])?["enum"] as? [String]
    }
    #expect(values("control") == Control.allCases.map(\.rawValue))
    #expect(
      Set(values("dpadControl") ?? []) == Set(Control.dpad.map(\.rawValue)),
      "dpadControl"
    )
    #expect(values("stickAxis") == Control.stickAxes.map(\.rawValue))
    #expect(values("axis") == RemappingAxis.allCases.map(\.rawValue))
    #expect(values("horizontalStickAxis") == ["LeftStickX", "RightStickX"])
    #expect(values("trigger") == ["LeftTrigger", "RightTrigger"])
  }

  // MARK: Crosswalk

  private struct Crosswalk: Decodable {
    struct Row: Decodable {
      struct HID: Decodable, Hashable {
        let page: String
        let usage: Int?
      }
      let w3cButton: Int?
      let w3cAxis: Int?
      let sdl: String?
      let evdev: String?
      let hid: [HID]
      let apple: String?
    }
    let controls: [String: Row]
  }

  private static func crosswalk() throws -> Crosswalk {
    let url = JSONSchemaFiles.directory.deletingLastPathComponent()
      .appendingPathComponent("Vocabulary/crosswalk.json")
    return try JSONDecoder().decode(Crosswalk.self, from: Data(contentsOf: url))
  }

  private static func vocabularyDefinitions() throws -> [String: Any] {
    try #require(
      try JSONSchemaFiles.document(named: "vocabulary.schema.json")["$defs"] as? [String: Any]
    )
  }

  @Test
  func crosswalkHasOneRowPerControl() throws {
    let rows = try Self.crosswalk().controls
    #expect(Set(rows.keys) == Set(Control.allCases.map(\.rawValue)))
    let definitions = try Self.vocabularyDefinitions()
    let schemaIDs = (definitions["control"] as? [String: Any])?["enum"] as? [String]
    #expect(Set(rows.keys) == Set(schemaIDs ?? []))
  }

  /// Each system name leads back to the control: the reverse index of a name contains its id.
  /// Two ids may share a name (`MISC1` is Capture and Microphone), so the index holds sets.
  @Test
  func crosswalkRoundTripsEveryControl() throws {
    let rows = try Self.crosswalk().controls
    var bySDL: [String: Set<String>] = [:]
    var byEvdev: [String: Set<String>] = [:]
    var byApple: [String: Set<String>] = [:]
    var byW3CButton: [Int: Set<String>] = [:]
    var byW3CAxis: [Int: Set<String>] = [:]
    var byHID: [Crosswalk.Row.HID: Set<String>] = [:]
    for (id, row) in rows {
      row.sdl.map { bySDL[$0, default: []].insert(id) }
      row.evdev.map { byEvdev[$0, default: []].insert(id) }
      row.apple.map { byApple[$0, default: []].insert(id) }
      row.w3cButton.map { byW3CButton[$0, default: []].insert(id) }
      row.w3cAxis.map { byW3CAxis[$0, default: []].insert(id) }
      for entry in row.hid { byHID[entry, default: []].insert(id) }
    }
    for control in Control.allCases {
      let id = control.rawValue
      let row = try #require(rows[id], "\(id)")
      #expect(row.sdl.map { bySDL[$0]?.contains(id) == true } ?? true, "\(id) sdl")
      #expect(row.evdev.map { byEvdev[$0]?.contains(id) == true } ?? true, "\(id) evdev")
      #expect(row.apple.map { byApple[$0]?.contains(id) == true } ?? true, "\(id) apple")
      #expect(row.w3cButton.map { byW3CButton[$0] == [id] } ?? true, "\(id) w3c button")
      #expect(row.w3cAxis.map { byW3CAxis[$0] == [id] } ?? true, "\(id) w3c axis")
      #expect(row.hid.allSatisfy { byHID[$0]?.contains(id) == true }, "\(id) hid")
      // Every id a name leads to is a vocabulary id.
      for ids in bySDL.values { #expect(ids.allSatisfy { Control(rawValue: $0) != nil }) }
    }
    #expect(bySDL["MISC1"] == ["Capture", "Microphone"])
  }

  @Test
  func crosswalkKeepsTheDocumentedFixedPoints() throws {
    let rows = try Self.crosswalk().controls
    #expect(rows["South"]?.sdl == "SOUTH")
    #expect(rows["South"]?.w3cButton == 0)
    #expect(rows["Back"]?.sdl == "BACK")
    #expect(rows["Back"]?.w3cButton == 8)
    #expect(rows["Guide"]?.w3cButton == 16)
    #expect(rows["LeftStickX"]?.w3cAxis == 0)
    #expect(rows["RightStickY"]?.w3cAxis == 3)
    #expect(rows["DpadRight"]?.w3cButton == 15)
    #expect(rows["South"]?.hid == [.init(page: "Button", usage: 1)])
  }
}
