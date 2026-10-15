import Foundation

/// Turns the `input` of a `MODIFIED` watch line into the `Frame` line that the endpoint's
/// `FeedRequest` flow accepts.
public enum FrameTranslation {
  private static let buttons: [String: String] = [
    "face-south": "south", "face-east": "east", "face-west": "west", "face-north": "north",
    "left-shoulder": "left_shoulder", "right-shoulder": "right_shoulder",
    "left-stick-click": "left_stick", "right-stick-click": "right_stick",
    "menu": "start", "view": "back", "guide": "guide", "share": "share",
    "touchpad-click": "touchpad", "microphone": "mute",
    "left-trigger-button": "left_trigger_click", "right-trigger-button": "right_trigger_click",
  ]
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
    frame["buttons"] = pressed.compactMap { buttons[$0] }
    frame["dpad"] = dpad[input["hat"] as? String ?? ""] ?? []
    var axes: [String: Double] = [:]
    for (key, name) in [("leftStick", "left_stick"), ("rightStick", "right_stick")] {
      let stick = input[key] as? [String: Any]
      axes["\(name)_x"] = unit(stick?["x"], scale: 32767, low: -1)
      axes["\(name)_y"] = unit(stick?["y"], scale: 32767, low: -1)
    }
    axes["left_trigger"] = unit(input["leftTrigger"], scale: 65535, low: 0)
    axes["right_trigger"] = unit(input["rightTrigger"], scale: 65535, low: 0)
    frame["axes"] = axes
    return (id, frame)
  }

  private static func unit(_ value: Any?, scale: Double, low: Double) -> Double {
    let raw = (value as? Double) ?? Double(value as? Int ?? 0)
    return min(max(raw, low * scale) / scale, 1)
  }
}
