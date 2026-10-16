import Foundation

/// The environment OJD gives a program it launches, so that SDL in the program lists the virtual
/// gamepads.
///
/// SDL reads `SDL_GAMECONTROLLERCONFIG` as mapping lines separated by newlines. OJD sets it to
/// the mapping line of each profile in `profiles`. A value already in the environment stays
/// first and OJD's lines follow it, so a mapping for the same GUID takes OJD's.
public enum SDLLaunchEnvironment {
  /// The variable that carries the mappings.
  public static let variable = "SDL_GAMECONTROLLERCONFIG"

  public enum Failure: Error, Equatable, Sendable {
    /// No profile was given, so there is no mapping to set.
    case noProfile
    case mapping(VirtualGamepadMappingError)
  }

  /// `base` with ``variable`` set to the mapping lines of `profiles`, each once, in the order of
  /// ``VirtualHIDProfileID/allCases``.
  public static func environment(
    adding profiles: [VirtualHIDProfileID],
    to base: [String: String]
  ) throws -> [String: String] {
    let ordered = VirtualHIDProfileID.allCases.filter(profiles.contains)
    guard !ordered.isEmpty else { throw Failure.noProfile }
    var lines: [String] = []
    for profile in ordered {
      do { lines.append(try profile.gamepadMapping().sdlMapping) } catch let error
        as VirtualGamepadMappingError
      {
        throw Failure.mapping(error)
      }
    }
    var environment = base
    let existing = (base[variable] ?? "").trimmingCharacters(in: .newlines)
    environment[variable] = ([existing].filter { !$0.isEmpty } + lines).joined(separator: "\n")
    return environment
  }
}
