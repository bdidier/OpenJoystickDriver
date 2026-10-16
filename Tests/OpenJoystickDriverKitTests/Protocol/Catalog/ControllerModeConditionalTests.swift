import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A record-level section that depends on a mode's protocol holds for every mode: the default
/// mode satisfies each rule here and a second mode breaks it.
struct ControllerModeConditionalTests {
  private static var hid: [String: Any] { ["family": "sony.sixaxis"] }
  private static var gip: [String: Any] { ["family": "xbox.gip"] }
  private static var hidMatch: [String: Any] {
    ["probes": [["report": 239, "length": 64, "expect": "answers"]]]
  }
  private static var usbMatch: [String: Any] { ["link": "usb"] }

  private static func record(
    default first: [String: Any],
    second: [String: Any],
    match: [String: Any],
    session: [String: Any]? = nil,
    fields: [String: Any]
  ) -> [String: Any] {
    var secondMode: [String: Any] = ["id": "second", "protocol": second, "match": match]
    if let session { secondMode["session"] = session }
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x1234, "productID": 0xABCD,
      "modes": [["id": "default", "protocol": first], secondMode],
    ]
    document.merge(fields) { _, new in new }
    return document
  }

  private static func problem(_ record: [String: Any]) -> String? {
    do {
      _ = try ControllerRecordSet.validate(JSONSerialization.data(withJSONObject: record))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error) }
  }

  private static func expectRejected(
    _ record: [String: Any],
    _ message: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let problem = Self.problem(record)
    #expect(
      problem?.contains(message) == true,
      "\(problem ?? "accepted")",
      sourceLocation: sourceLocation
    )
  }

  @Test
  func usbNeedsEveryModeRawUSB() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["usb": ["configuration": "set1-before-claim"]]
      ),
      "USB overrides require a raw-USB protocol family"
    )
  }

  @Test
  func serverNeedsEveryModeHID() {
    Self.expectRejected(
      Self.record(
        default: Self.hid,
        second: Self.gip,
        match: Self.usbMatch,
        fields: ["server": "ojd"]
      ),
      "server applies only to HID controllers"
    )
  }

  @Test
  func routeNeedsEveryModeRawUSB() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["route": "ExtensionOwned"]
      ),
      "route ExtensionOwned applies only to raw-USB controllers"
    )
  }

  @Test
  func aSessionFollowsTheProtocolOfItsOwnMode() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        session: ["settleMilliseconds": 200],
        fields: [:]
      ),
      "session settleMilliseconds applies only to raw-USB modes"
    )
  }

  @Test
  func tuningKeysAreReadByEveryMode() {
    Self.expectRejected(
      Self.record(
        default: ["family": "sony.dualshock4"],
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["tuning": ["inputLivenessTimeoutMs": 500]]
      ),
      "inputLivenessTimeoutMs is not read by the sony.sixaxis driver"
    )
  }

  @Test
  func bluetoothLENeedsEveryModeSwitch2() {
    Self.expectRejected(
      Self.record(
        default: ["family": "nintendo.switch2"],
        second: Self.hid,
        match: Self.hidMatch,
        fields: [
          "bluetoothLE": ["vibrationCharacteristic": "00000000-0000-0000-0000-000000000000"]
        ]
      ),
      "bluetoothLE requires a Switch 2 controller"
    )
  }

  @Test
  func usbEndpointsDifferFromEveryModeDefault() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: ["family": "xbox.xusb", "variant": "wired"],
        match: Self.usbMatch,
        fields: ["usb": ["endpoints": ["in": 129, "out": 1]]]
      ),
      "protocol-default endpoints must be omitted"
    )
  }

  @Test
  func aHIDUsageMapNeedsEveryModeHIDDescriptor() {
    let usage: [String: Any] = ["kind": "button", "page": 9, "usage": 1, "control": "South"]
    Self.expectRejected(
      Self.record(
        default: ["family": "hid.descriptor"],
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["input": ["hidUsageMap": ["usages": [usage]]]]
      ),
      "a HID usage map applies only to hid.descriptor in every mode"
    )
  }

  @Test
  func presentControlsAreDeclaredByTheDriverOfEveryMode() {
    let present =
      (ProtocolDescription.bundled[.sonyDualSense]?.recordCapabilities.presentControls ?? [])
      .map(\.rawValue).sorted()
    Self.expectRejected(
      Self.record(
        default: ["family": "sony.dualsense"],
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["capabilities": ["present": present]]
      ),
      "capabilities must be deltas the driver of every mode declares"
    )
  }
}
