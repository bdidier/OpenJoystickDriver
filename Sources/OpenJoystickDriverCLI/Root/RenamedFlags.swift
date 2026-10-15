import Foundation
import OpenJoystickDriverKit

/// Names the new word when a command line uses a flag or command group that 0.6.0 renamed to an
/// OS-neutral word. The old word is still refused; this only explains the refusal. The words come
/// from the one table of old words, ``RenamedWord/all``.
enum RenamedFlags {
  /// The rename that `arguments` trips, or nil when no renamed flag is used.
  static func match(arguments: [String]) -> RenamedWord? {
    let typed = arguments[..<(arguments.firstIndex(of: "--") ?? arguments.endIndex)]
    if let group = commandGroup(in: Array(typed)),
      let word = RenamedWord.all.first(where: { $0.kind == .command && $0.old == group })
    {
      return word
    }
    return RenamedWord.all.first { word in
      guard case .flag(let command) = word.kind else { return false }
      return typed.contains(command)
        && typed.contains { $0 == word.old || $0.hasPrefix(word.old + "=") }
    }
  }

  /// The first word that is not an option or the value of `--timeout`: the command group.
  private static func commandGroup(in typed: [String]) -> String? {
    var skipValue = false
    for argument in typed {
      if skipValue {
        skipValue = false
        continue
      }
      if argument == "--timeout" {
        skipValue = true
        continue
      }
      if !argument.hasPrefix("-") { return argument }
    }
    return nil
  }
}
