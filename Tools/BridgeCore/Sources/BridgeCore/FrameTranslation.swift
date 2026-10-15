import Foundation

/// Turns the `input` of a `MODIFIED` watch line into the `Frame` line that the endpoint's
/// `FeedRequest` flow accepts.
public enum FrameTranslation {
  private static let dpad: [String: [String]] = [
    "north": ["up"], "northEast": ["up", "right"], "east": ["right"],
    "southEast": ["down", "right"], "south": ["down"], "southWest": ["down", "left"],
    "west": ["left"], "northWest": ["up", "left"],
  ]

  /// The watch line's controller `id` and `Frame`, or nil when the line is not a `MODIFIED` line
  /// with an input state.
  public static func frame(
    fromWatchLine line: [String: Any]
  ) -> (id: String, frame: [String: Any])? {
    guard line["type"] as? String == "MODIFIED",
      let object = line["object"] as? [String: Any], let id = object["id"] as? String,
      let input = object["input"] as? [String: Any]
    else { return nil }
    let pressed = (input["pressed"] as? [String]) ?? []
    var frame: [String: Any] = ["apiVersion": endpointAPIVersion, "kind": "Frame"]
    frame["buttons"] = pressed.filter { PeerMessage.buttons.contains($0) }
    frame["dpad"] = dpad[input["hat"] as? String ?? ""] ?? []
    var axes: [String: Double] = [:]
    for (key, name) in [("leftStick", "LeftStick"), ("rightStick", "RightStick")] {
      let stick = input[key] as? [String: Any]
      axes["\(name)X"] = unit(stick?["x"], scale: 32767, low: -1)
      axes["\(name)Y"] = unit(stick?["y"], scale: 32767, low: -1)
    }
    axes["LeftTrigger"] = unit(input["leftTrigger"], scale: 65535, low: 0)
    axes["RightTrigger"] = unit(input["rightTrigger"], scale: 65535, low: 0)
    frame["axes"] = axes
    return (id, frame)
  }

  private static func unit(_ value: Any?, scale: Double, low: Double) -> Double {
    let raw = (value as? Double) ?? Double(value as? Int ?? 0)
    return min(max(raw, low * scale) / scale, 1)
  }
}
