import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

/// The permission, publisher, application, and modifier rows of the OS-neutral vocabulary: each
/// old word is refused, and the refusal names the new word.
@Suite(.serialized)
struct AccessWordsTests {
  /// The old permission id and the id that replaced it.
  private static let permissionIDs = [
    ("input-monitoring", "input-read"),
    ("accessibility", "input-inject"),
    ("driver-extension", "usb-transport"),
  ]

  private static func hint(_ old: String, _ new: String) -> String {
    "'\(old)' was renamed to '\(new)'."
  }

  private func run(_ arguments: [String]) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(arguments + ["--timeout", "5"])
    }
  }

  @Test(arguments: permissionIDs)
  func anOldPermissionIDIsRefusedAndNamesTheNewOne(old: String, new: String) async {
    let result = await run(["permission", "request", old])

    #expect(result.code == 64)
    #expect(result.standardError.contains(Self.hint(old, new)))
  }

  @Test(arguments: permissionIDs)
  func theOldPermissionIDIsNotAnIDAndTheNewOneIs(old: String, new: String) {
    #expect(PermissionID(rawValue: old) == nil)
    #expect(PermissionID(rawValue: new) != nil)
  }

  @Test
  func everyRenamedWordHasALocalizedHintThatNamesBothWords() {
    #expect(!RenamedWord.all.isEmpty)
    for word in RenamedWord.all {
      let hint = word.hint()
      #expect(hint.contains(word.old), "\(word.old)")
      #expect(hint.contains(word.new), "\(word.old)")
    }
  }

  @Test
  func theFlagHintsAndTheWordHintsComeFromTheOneTable() {
    let flag = RenamedFlags.match(arguments: ["diagnose", "--bundle", "x"])

    #expect(flag == RenamedWord.replacement(for: "--bundle", kind: .flag(command: "diagnose")))
    #expect(flag?.new == "--output")
  }

  @Test(arguments: [("team", "signed"), ("apple", "platform")])
  func anOldPublisherKindIsRefusedAndNamesTheNewOne(old: String, new: String) {
    let json = Data(#""\#(old)""#.utf8)

    #expect {
      _ = try JSONDecoder().decode(CodeSigningIdentity.Kind.self, from: json)
    } throws: { error in
      String(describing: error).contains(Self.hint(old, new))
    }
    #expect {
      _ = try JSONDecoder().decode(AccessIdentityKind.self, from: json)
    } throws: { error in
      String(describing: error).contains(Self.hint(old, new))
    }
  }

  @Test(arguments: [
    ("identityKind", "publisher.kind"), ("teamIdentifier", "publisher.id"),
    ("bundleIdentifier", "appID"), ("inputMonitoring", "inputRead"),
    ("accessibility", "inputInject"),
  ])
  func anOldFieldNameHasAHintThatNamesTheNewOne(old: String, new: String) {
    #expect(RenamedWord.hints(for: [old], kind: .field).contains(Self.hint(old, new)))
  }

  @Test
  func anOldApplicationKeyInAProfileIsRefusedAndNamesAppID() {
    let document = ProfileSchemaTests.richDocument.replacingOccurrences(
      of: #""appID""#,
      with: #""bundleIdentifier""#
    )

    #expect {
      _ = try RemappingProfileFileStore.load(from: Data(document.utf8))
    } throws: { error in
      String(describing: error).contains(Self.hint("bundleIdentifier", "appID"))
    }
  }

  @Test(arguments: [("command", "meta"), ("option", "alt")])
  func anOldModifierInAProfileIsRefusedAndNamesTheNewOne(old: String, new: String) {
    let document = ProfileSchemaTests.richDocument.replacingOccurrences(
      of: #""shift", "meta""#,
      with: #""shift", "\#(old)""#
    )

    #expect {
      _ = try RemappingProfileFileStore.load(from: Data(document.utf8))
    } throws: { error in
      String(describing: error).contains(Self.hint(old, new))
    }
  }

  @Test(arguments: [("command", "meta"), ("option", "alt")])
  func anOldModifierInATargetIsRefusedAndNamesTheNewOne(old: String, new: String) {
    #expect {
      _ = try parseTarget("key:a:mods=shift,\(old)")
    } throws: { error in
      ((error as? CLIFailure)?.message ?? "").contains(Self.hint(old, new))
    }
  }

  @Test
  func theAppOptionIsAnAppIDAndTheOldFlagIsRefused() async {
    let help = await run(["profile", "create", "--help"])
    let old = await run([
      "profile", "create", "Pad", "--controller", "045E:028E", "--bundle-id", "x.y",
    ])

    #expect(help.standardOutput.contains("app-id"))
    #expect(!help.standardOutput.contains("bundle-id"))
    #expect(old.code == 64)
  }
}
