import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  @Test
  func profileWithRemovedGyroFieldIsRecoveredAsDamaged() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let legacy = makeProfile(name: "Legacy")
      try await library.create(valid)
      var legacyObject = try #require(
        JSONSerialization.jsonObject(
          with: Data(RemappingProfileFileStore.encodedJSON(legacy).utf8)
        ) as? [String: Any]
      )
      legacyObject["gyroOutput"] = ["mode": "mouse", "virtualMotion": true]
      try JSONSerialization.data(withJSONObject: legacyObject)
        .write(to: library.profileURL(legacy.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
    }
  }

  /// A stored profile that still names a control by a removed spelling is refused like any
  /// other damaged profile: dropped from the snapshot, reported, its bytes left as they were.
  @Test(arguments: ["south", "face-south", "share", "options", "left_trigger_click", "view"])
  func profileWithRemovedControlNameIsRecoveredAsDamaged(oldName: String) async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Stored")
      try await library.create(valid)
      var object = try #require(
        JSONSerialization.jsonObject(
          with: Data(RemappingProfileFileStore.encodedJSON(stored).utf8)
        ) as? [String: Any]
      )
      object["bindings"] = [
        [
          "id": UUID().uuidString,
          "source": ["type": "button", "button": oldName],
          "destination": ["type": "keyboard", "key": "space", "modifiers": [String]()],
        ] as [String: Any]
      ]
      let bytes = try JSONSerialization.data(withJSONObject: object)
      try bytes.write(to: library.profileURL(stored.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
      #expect(try Data(contentsOf: library.profileURL(stored.id)) == bytes)
    }
  }

  @Test
  func profileWithCurrentControlNameLoads() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Stored")
      try await library.create(valid)
      var object = try #require(
        JSONSerialization.jsonObject(
          with: Data(RemappingProfileFileStore.encodedJSON(stored).utf8)
        ) as? [String: Any]
      )
      object["bindings"] = [
        [
          "id": UUID().uuidString,
          "source": ["type": "button", "button": "South"],
          "destination": ["type": "keyboard", "key": "space", "modifiers": [String]()],
        ] as [String: Any]
      ]
      try JSONSerialization.data(withJSONObject: object).write(to: library.profileURL(stored.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(Set(snapshot.profiles.map(\.id)) == [valid.id, stored.id])
      #expect(snapshot.issues.isEmpty)
    }
  }
}
