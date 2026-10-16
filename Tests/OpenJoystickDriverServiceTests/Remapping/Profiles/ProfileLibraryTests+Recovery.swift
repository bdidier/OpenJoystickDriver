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

  /// Each profile file the library cannot use is reported with the code a request gives the same
  /// failure.
  @Test
  func damagedProfileIssuesCarryTheCodeOfTheirSituation() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      try await library.create(valid)
      let invalidHeader = Data(
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"Profile","name":"Pad"}"#.utf8
      )
      let unsupported = Data(#"{"apiVersion":"unsupported.example/v9","kind":"Profile"}"#.utf8)
      let misnamed = makeProfile(name: "Misnamed")
      let duplicate = makeProfile(name: "valid")
      try invalidHeader.write(to: library.profileURL(UUID()))
      try unsupported.write(to: library.profileURL(UUID()))
      try Data(RemappingProfileFileStore.encodedJSON(misnamed).utf8)
        .write(to: library.profileURL(UUID()))
      try Data(RemappingProfileFileStore.encodedJSON(duplicate).utf8)
        .write(to: library.profileURL(duplicate.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.issues.allSatisfy { $0.kind == .damagedProfile })
      let codes = Set(snapshot.issues.map(\.code))
      let expected: Set<ErrorCode> = [
        .corruptLibrary, .duplicateName, .invalidProfile, .unsupportedAPIVersion,
      ]
      #expect(codes == expected)
      #expect(snapshot.issues.count == 4)
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
