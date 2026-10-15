import Foundation

/// Names the new flag when a command line uses a flag that 0.6.0 renamed to an OS-neutral word.
/// The old flag is still refused; this only explains the refusal.
enum RenamedFlags {
  struct Rename: Equatable {
    /// The command the flag belongs to, as typed.
    let command: String
    let old: String
    let new: String
  }

  static let renames: [Rename] = [
    Rename(command: "diagnose", old: "--bundle", new: "--output")
  ]

  /// The rename that `arguments` trips, or nil when no renamed flag is used.
  static func match(arguments: [String]) -> Rename? {
    let typed = arguments[..<(arguments.firstIndex(of: "--") ?? arguments.endIndex)]
    return renames.first { rename in
      typed.contains(rename.command)
        && typed.contains { $0 == rename.old || $0.hasPrefix(rename.old + "=") }
    }
  }
}
