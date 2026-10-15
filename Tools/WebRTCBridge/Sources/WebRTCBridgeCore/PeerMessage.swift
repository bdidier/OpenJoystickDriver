import Foundation

/// Checks the messages that a peer sends over the data channel. The peer is not trusted: a
/// message that is too long, is not JSON, or does not have the shape of its endpoint line is
/// dropped, and a message that passes is rebuilt from the checked fields.
public enum PeerMessage {
  /// The longest message the bridge reads, and the longest signaling blob.
  public static let maximumBytes = 64 * 1024
  /// The longest `holdMilliseconds` of a `Frame`, as in `Resources/Schemas/endpoint.schema.json`.
  public static let maximumHoldMilliseconds = 60_000
  /// The longest `durationMilliseconds` of a `setRumble`, as in `cli-output.schema.json`.
  public static let maximumRumbleMilliseconds = 5000

  private static let buttons: Set<String> = [
    "south", "east", "west", "north", "left_shoulder", "right_shoulder", "left_stick",
    "right_stick", "start", "back", "guide", "share", "options", "touchpad", "mute",
    "left_trigger_click", "right_trigger_click", "left_grip", "right_grip", "left_pad_click",
    "right_pad_click", "left_sl", "left_sr", "right_sl", "right_sr", "left_function",
    "right_function", "left_paddle", "right_paddle",
  ]
  private static let dpad: Set<String> = ["up", "down", "left", "right"]
  private static let axes: Set<String> = [
    "left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y", "left_trigger",
    "right_trigger",
  ]
  private static let frameKeys: Set<String> = [
    "apiVersion", "kind", "buttons", "dpad", "axes", "holdMilliseconds",
  ]
  private static let intensities: Set<String> = [
    "leftMain", "rightMain", "leftTrigger", "rightTrigger", "leftHaptic", "rightHaptic",
  ]
  private static let rumbleKeys: Set<String> = [
    "apiVersion", "kind", "type", "intensities", "durationMilliseconds",
  ]

  /// The `Frame` in the message, or nil when the message is not a valid `Frame`.
  public static func frame(from data: Data) -> [String: Any]? {
    guard let line = object(from: data), keys(of: line, within: frameKeys), header(line, "Frame")
    else { return nil }
    var frame: [String: Any] = ["apiVersion": endpointAPIVersion, "kind": "Frame"]
    if let value = line["buttons"] {
      guard let names = unique(value, within: buttons) else { return nil }
      frame["buttons"] = names
    }
    if let value = line["dpad"] {
      guard let names = unique(value, within: dpad) else { return nil }
      frame["dpad"] = names
    }
    if let value = line["axes"] {
      guard let object = value as? [String: Any], Set(object.keys).isSubset(of: axes) else {
        return nil
      }
      var checked: [String: Double] = [:]
      for (name, number) in object {
        guard let number = real(number) else { return nil }
        checked[name] = number
      }
      frame["axes"] = checked
    }
    if let value = line["holdMilliseconds"] {
      guard let hold = integer(value), (0...maximumHoldMilliseconds).contains(hold) else {
        return nil
      }
      frame["holdMilliseconds"] = hold
    }
    return frame
  }

  /// The `RumbleCommand` in the message, or nil when the message is not a valid one. The shape is
  /// that of `sharedVirtualFeedLine` in `Resources/Schemas/cli-output.schema.json`: `setRumble`
  /// has all six intensities and an optional duration of 0 to 5000 ms, and `stopRumble` has no
  /// member besides the header and `type`.
  public static func rumble(from data: Data) -> [String: Any]? {
    guard let line = object(from: data), keys(of: line, within: rumbleKeys),
      header(line, "RumbleCommand"), let type = line["type"] as? String
    else { return nil }
    var command: [String: Any] = [
      "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": type,
    ]
    switch type {
    case "stopRumble":
      return line.count == 3 ? command : nil
    case "setRumble":
      guard let object = line["intensities"] as? [String: Any], Set(object.keys) == intensities
      else { return nil }
      var checked: [String: Int] = [:]
      for (name, number) in object {
        guard let level = integer(number), (0...65535).contains(level) else { return nil }
        checked[name] = level
      }
      command["intensities"] = checked
      if let value = line["durationMilliseconds"] {
        guard let duration = integer(value), (0...maximumRumbleMilliseconds).contains(duration)
        else { return nil }
        command["durationMilliseconds"] = duration
      }
      return command
    default:
      return nil
    }
  }

  private static func object(from data: Data) -> [String: Any]? {
    guard data.count <= maximumBytes else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private static func keys(of line: [String: Any], within allowed: Set<String>) -> Bool {
    Set(line.keys).isSubset(of: allowed)
  }

  private static func header(_ line: [String: Any], _ kind: String) -> Bool {
    line["apiVersion"] as? String == endpointAPIVersion && line["kind"] as? String == kind
  }

  private static func unique(_ value: Any, within allowed: Set<String>) -> [String]? {
    guard let names = value as? [String], Set(names).count == names.count,
      Set(names).isSubset(of: allowed)
    else { return nil }
    return names
  }

  private static func isBoolean(_ value: Any) -> Bool {
    CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID()
  }

  private static func real(_ value: Any) -> Double? {
    guard !isBoolean(value), let double = value as? Double, double.isFinite else { return nil }
    return double
  }

  private static func integer(_ value: Any) -> Int? {
    guard let double = real(value), double == double.rounded(), abs(double) < 1e15 else {
      return nil
    }
    return Int(double)
  }
}

/// Holds the newest `Frame` of the peer for the one thread that sends to the endpoint. A frame
/// that is replaced before it is taken is dropped, so a peer that sends faster than the endpoint
/// plays cannot fill the endpoint's queue.
public final class FrameMailbox: @unchecked Sendable {
  private let condition = NSCondition()
  private var pending: [String: Any]?

  public init() {}

  /// Never blocks for long, so it can run on the WebRTC callback thread.
  public func post(_ frame: [String: Any]) {
    condition.lock()
    pending = frame
    condition.signal()
    condition.unlock()
  }

  /// The newest posted frame, or nil when none is posted within `timeout`. The frame is checked
  /// under the lock that `post` takes, so a post that races the timeout is returned, not lost, and
  /// leaves nothing behind that would end a later wait early.
  public func next(timeout: TimeInterval) -> [String: Any]? {
    let deadline = Date(timeIntervalSinceNow: timeout)
    condition.lock()
    defer { condition.unlock() }
    while pending == nil {
      if !condition.wait(until: deadline) { break }
    }
    let frame = pending
    pending = nil
    return frame
  }
}
