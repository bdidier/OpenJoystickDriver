import Foundation
import OpenJoystickDriverKit

/// Names the new flag when a command line uses a flag that 0.6.0 renamed to an OS-neutral word.
/// The old flag is still refused; this only explains the refusal. The flags come from the one
/// table of old words, ``RenamedWord/all``.
enum RenamedFlags {
  /// The rename that `arguments` trips, or nil when no renamed flag is used.
  static func match(arguments: [String]) -> RenamedWord? {
    let typed = arguments[..<(arguments.firstIndex(of: "--") ?? arguments.endIndex)]
    return RenamedWord.all.first { word in
      guard case .flag(let command) = word.kind else { return false }
      return typed.contains(command)
        && typed.contains { $0 == word.old || $0.hasPrefix(word.old + "=") }
    }
  }
}
