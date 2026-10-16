import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  @Test
  func profileWithUnknownFieldIsRecoveredAsDamaged() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Unknown")
      try await library.create(valid)
      var storedObject = try #require(
        JSONSerialization.jsonObject(
          with: Data(RemappingProfileFileStore.encodedJSON(stored).utf8)
        ) as? [String: Any]
      )
      storedObject["notAField"] = true
      try JSONSerialization.data(withJSONObject: storedObject)
        .write(to: library.profileURL(stored.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
    }
  }

  /// A stored profile that names a control the vocabulary does not have is damaged like any
  /// other: dropped from the snapshot, reported, its bytes left as they were.
  @Test(arguments: ["NotAControl", "a", ""])
  func profileWithUnknownControlNameIsRecoveredAsDamaged(name: String) async throws {
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
          "source": ["type": "button", "button": name],
          "destination": ["type": "keyboard", "key": "Space", "modifiers": [String]()],
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
          "destination": ["type": "keyboard", "key": "Space", "modifiers": [String]()],
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
