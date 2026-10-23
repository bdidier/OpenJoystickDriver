import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CLIOutputValueSpellingTests {
  private static func decodes<Value: Decodable>(_ type: Value.Type, _ raw: String) -> Bool {
    (try? JSONDecoder().decode(type, from: Data("\"\(raw)\"".utf8))) != nil
  }

  @Test
  func recordLayersAndOperationsAreUpperCamelCase() {
    #expect(
      ControllerRecordLayer.allCases.map(\.rawValue)
        == ["Driver", "Bundled", "Package", "Global", "User", "Profile"]
    )
    #expect(ControllerRecordOperation.add.rawValue == "Add")
    #expect(ControllerRecordOperation.patch.rawValue == "Patch")
    for raw in ["driver", "bundled", "package", "global", "user", "profile", "add", "patch"] {
      #expect(!Self.decodes(ControllerRecordLayer.self, raw), "\(raw)")
      #expect(!Self.decodes(ControllerRecordOperation.self, raw), "\(raw)")
    }
  }

  @Test
  func ownershipValuesAreUpperCamelCaseWithUpperCaseAcronyms() {
    #expect(DeviceDiscoverySource.hid.rawValue == "HID")
    #expect(DeviceDiscoverySource.rawUSB.rawValue == "RawUSB")
    #expect(ControllerOwnershipObservation.exclusiveHID.rawValue == "ExclusiveHID")
    #expect(ControllerOwnershipObservation.exclusiveRawUSB.rawValue == "ExclusiveRawUSB")
    #expect(DuplicateExposureRisk.none.rawValue == "None")
    #expect(HIDInputOwnership.ownedByAnotherClient.rawValue == "OwnedByAnotherClient")
    for raw in ["hid", "rawUSB", "Hid", "RawUsb", "exclusiveHID", "unknown", "none"] {
      #expect(!Self.decodes(DeviceDiscoverySource.self, raw), "\(raw)")
    }
    for raw in ["exclusiveHID", "exclusiveRawUSB", "ExclusiveHid", "unknown"] {
      #expect(ControllerOwnershipObservation(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["none", "unknownOwnership", "upstreamVirtualDevice"] {
      #expect(DuplicateExposureRisk(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["unknown", "exclusive", "shared", "accessDenied", "ownedByAnotherClient"] {
      #expect(HIDInputOwnership(rawValue: raw) == nil, "\(raw)")
    }
  }

  @Test
  func notPublishedReasonsAreUpperCamelCaseAndRefuseOtherSpellingsAndFailureText() throws {
    #expect(
      ApplicationServicePublicationStatus.NotPublishedReason.allCases.map(\.rawValue) == [
        "OutputDisabled", "SystemGamepad", "NativeHIDPassThrough", "UpstreamVirtualDevice",
        "SessionSuspended", "NoVirtualProfile", "Suppressed", "NoInputYet", "HeldByAnotherClient",
      ]
    )
    for raw in [
      "outputDisabled", "systemGamepad", "nativeHIDPassThrough", "native-hid-pass-through",
      "NativeHidPassThrough", "noInputYet", "send failed", "",
    ] {
      #expect(!Self.decodes(ApplicationServicePublicationStatus.NotPublishedReason.self, raw))
      let json = #"{"state":"NotPublished","reason":"\#(raw)"}"#
      #expect(
        (try? JSONDecoder().decode(ApplicationServicePublicationStatus.self, from: Data(json.utf8)))
          == nil,
        "\(raw)"
      )
    }
    let failed = ApplicationServicePublicationStatus.failed("send failed")
    let decoded = try JSONDecoder().decode(
      ApplicationServicePublicationStatus.self,
      from: JSONEncoder().encode(failed)
    )
    #expect(decoded == failed)
    #expect(decoded.reason == nil)
  }

  @Test
  func stateValuesAreUpperCamelCase() {
    #expect(ApplicationServicePublicationStatus.State.notPublished.rawValue == "NotPublished")
    #expect(OutputDisabledReason.noVirtualProfile.rawValue == "NoVirtualProfile")
    #expect(VirtualHIDProfileOverrideScope.unit.rawValue == "Unit")
    #expect(DiagnoseStatus.skip.rawValue == "Skip")
    #expect(ApplicationServiceLogStream.standardOutput.rawValue == "StandardOutput")
    #expect(CommandLineToolLinkStatus.State.blockedByFile.rawValue == "BlockedByFile")
    #expect(PermissionManager.AccessState.granted.rawValue == "Granted")
    #expect(
      ApplicationServiceRemappingProfileIssue.Kind.unusableLibrary.rawValue == "UnusableLibrary"
    )
    #expect(PacketLogDirection.received.rawValue == "Rx")
    for raw in ["notPublished", "published", "failed", "not-published"] {
      #expect(!Self.decodes(ApplicationServicePublicationStatus.State.self, raw), "\(raw)")
    }
    for raw in ["userDisabled", "upstreamVirtualDevice", "noVirtualProfile"] {
      #expect(OutputDisabledReason(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["unit", "model"] { #expect(VirtualHIDProfileOverrideScope(rawValue: raw) == nil) }
    for raw in ["standardOutput", "standardError"] {
      #expect(ApplicationServiceLogStream(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["installed", "linkedElsewhere", "broken", "blockedByFile", "missing"] {
      #expect(CommandLineToolLinkStatus.State(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["granted", "denied", "unknown", "GRANTED"] {
      #expect(PermissionManager.AccessState(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["damagedProfile", "unusableLibrary"] {
      #expect(ApplicationServiceRemappingProfileIssue.Kind(rawValue: raw) == nil, "\(raw)")
    }
    for raw in ["rx", "tx"] { #expect(PacketLogDirection(rawValue: raw) == nil, "\(raw)") }
  }

  @Test
  func outputOutcomesAreUpperCamelCase() {
    for raw in ["delivered", "notFound", "unsupportedCapability", "cancelled"] {
      #expect(ControllerOutputResult.Outcome(rawValue: raw) == nil, "\(raw)")
    }
    #expect(ControllerOutputResult.Outcome(rawValue: "NotFound") == .notFound)
  }

  @Test
  func bindingGrammarPartsAreKebabCase() throws {
    #expect(
      try RemappingCommandValueParser.source("axis:left-stick-x:negative")
        == .axisDirection(.leftStickX, .negative)
    )
    #expect(try RemappingCommandValueParser.source("dpad:dpad-up") == .dpad(.up))
    #expect(
      try RemappingCommandValueParser.destination("key:key-a:mods=meta,shift")
        == .keyboard(key: .a, modifiers: [.meta, .shift])
    )
    for raw in [
      "axis:LeftStickX:Negative", "axis:leftStickX:negative", "axis:left-stick-x:Negative",
      "button:South", "dpad:DpadUp",
    ] {
      #expect(throws: RemappingCommandValueError.self, "\(raw)") {
        try RemappingCommandValueParser.source(raw)
      }
    }
    for raw in [
      "key:KeyA", "key:key-a:mods=Meta", "gamepad:button:South", "gamepad:axis:LeftStickX",
    ] {
      #expect(throws: RemappingCommandValueError.self, "\(raw)") {
        try RemappingCommandValueParser.destination(raw)
      }
    }
  }

  @Test
  func everyBindingGrammarEnumHasOneKebabSpellingPerCase() {
    #expect(CommandLineName.collisions(in: Control.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingAxis.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingAxisDirection.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingDpadDirection.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingKeyboardKey.self).isEmpty)
    #expect(CommandLineName.collisions(in: RemappingKeyModifier.self).isEmpty)
    for key in RemappingKeyboardKey.allCases {
      #expect(CommandLineName.value(of: CommandLineName.kebab(key.rawValue)) == key)
    }
  }
}
