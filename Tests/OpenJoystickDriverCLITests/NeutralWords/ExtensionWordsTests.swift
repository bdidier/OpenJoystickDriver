import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

/// The transport-extension rows of the OS-neutral vocabulary: each old word is refused, and the
/// refusal names the new word. Every hint comes from the one table, ``RenamedWord/all``.
@Suite(.serialized)
struct ExtensionWordsTests {
  private static func hint(_ old: String, _ new: String) -> String {
    "'\(old)' was renamed to '\(new)'."
  }

  private func run(_ arguments: [String]) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(arguments + ["--timeout", "5"])
    }
  }

  @Test(arguments: [["extension"], ["extension", "status"], ["extension", "activate", "--json"]])
  func theOldCommandIsRefusedAndNamesTheNewOne(arguments: [String]) async {
    let result = await run(arguments)

    #expect(result.code == 64)
    #expect(result.standardError.contains(Self.hint("extension", "transport-extension")))
  }

  @Test
  func theOldCommandIsRefusedAfterAnOptionToo() async {
    let result = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(["--timeout", "5", "extension", "status"])
    }

    #expect(result.code == 64)
    #expect(result.standardError.contains(Self.hint("extension", "transport-extension")))
  }

  @Test(arguments: [
    ("driverKitOwnedUSB", "ExtensionOwnedUsb"), ("nativeGamepad", "SystemGamepad"),
    ("nativeHIDVisible", "SystemHidVisible"),
  ])
  func anOldPhysicalOwnershipIsRefusedAndNamesTheNewOne(old: String, new: String) {
    let json = Data(#""\#(old)""#.utf8)

    #expect {
      _ = try JSONDecoder().decode(ControllerOwnershipObservation.self, from: json)
    } throws: { error in
      String(describing: error).contains(Self.hint(old, new))
    }
    #expect(
      RenamedWord.hints(for: [old], kind: .physicalOwnership).contains(Self.hint(old, new))
    )
  }

  @Test
  func anOldDuplicateExposureRiskIsRefused() {
    let json = Data(#""nativeHIDVisible""#.utf8)

    #expect {
      _ = try JSONDecoder().decode(DuplicateExposureRisk.self, from: json)
    } throws: { error in
      String(describing: error).contains(Self.hint("nativeHIDVisible", "SystemHidVisible"))
    }
  }

  @Test(arguments: ["ExtensionOwnedUsb", "SystemGamepad", "SystemHidVisible"])
  func theNewPhysicalOwnershipIsAccepted(name: String) throws {
    let json = Data(#""\#(name)""#.utf8)
    let value = try JSONDecoder().decode(ControllerOwnershipObservation.self, from: json)

    #expect(value.rawValue == name)
  }

  @Test(arguments: [
    ("usbExtension", "transportClaim", RenamedWord.Kind.field),
    ("claims", "claimed", .transportClaim), ("doesNotClaim", "unclaimed", .transportClaim),
    ("DriverExtension", "TransportExtension", .outputKind),
    ("extension-bundle", "transport-extension-bundle", .checkID),
    ("extension-registration", "transport-extension-registration", .checkID),
    ("nativeGamepad", "systemGamepad", .publicationReason),
  ])
  func anOldWordHasAHintThatNamesTheNewOne(old: String, new: String, kind: RenamedWord.Kind) {
    #expect(RenamedWord.hints(for: [old], kind: kind).contains(Self.hint(old, new)))
  }

  @Test
  func everyRowOfTheTransportExtensionWordsHasAHintThatNamesBothWords() {
    let rows = RenamedWord.all.filter {
      switch $0.kind {
      case .command, .physicalOwnership, .transportClaim, .outputKind, .checkID,
        .publicationReason:
        true
      default: false
      }
    }
    #expect(rows.count == 10)
    for word in rows {
      #expect(word.hint().contains(word.old), "\(word.old)")
      #expect(word.hint().contains(word.new), "\(word.old)")
    }
  }

  @Test
  func theDiagnoseChecksUseTheNewIDs() {
    let ids = DiagnosticsService.extensionChecks(
      ExtensionStatus(bundle: .missing, registration: .absent)
    ).map(\.id)

    #expect(ids == ["transport-extension-bundle", "transport-extension-registration"])
  }
}
