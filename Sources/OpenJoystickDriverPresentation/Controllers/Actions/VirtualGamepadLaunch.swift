import Foundation
import OpenJoystickDriverKit

/// Runs a game with the SDL mapping of the connected virtual gamepads, as `ojd virtual launch`
/// does.
enum VirtualGamepadLaunch {
  /// A program ready to start.
  struct Prepared {
    let executable: URL
    let environment: [String: String]
  }

  enum Failure: Error, Equatable {
    /// No connected controller has a virtual gamepad, so there is no mapping to set.
    case noGamepad
    /// The program cannot start; `reason` says why.
    case cannotStart(program: String, reason: String)

    /// The message the user reads.
    var message: String {
      switch self {
      case .noGamepad: OJDLocalized.string("controllers.launch.noGamepad")
      case .cannotStart(let program, let reason):
        OJDLocalized.formatted("cli.virtual.launch.error.failed", program, reason)
      }
    }
  }

  /// What became of a started program.
  enum Outcome: Equatable {
    case started(program: String)
    case exited(program: String, status: Int32)
    case failed(String)

    var message: String {
      switch self {
      case .started(let program): OJDLocalized.formatted("controllers.launch.started", program)
      case .exited(let program, let status):
        OJDLocalized.formatted("controllers.launch.exited", program, Int(status))
      case .failed(let message): message
      }
    }
  }

  /// The executable of `program`, an `.app` or an executable file, and `baseEnvironment` with the
  /// mappings of every virtual gamepad in `devices`. `gameControllerBackend` adds the SDL hints
  /// that make SDL read controllers only through Apple's GameController framework.
  static func prepare(
    program: URL,
    devices: [ApplicationServiceDeviceDescription],
    gameControllerBackend: Bool,
    baseEnvironment: [String: String]
  ) throws -> Prepared {
    let executable: URL
    do {
      executable = try ProgramExecutable.url(for: program.path, searchPath: nil)
    } catch {
      let reason: String
      switch error as? ProgramExecutable.Failure {
      case .noExecutable?: reason = OJDLocalized.string("cli.virtual.launch.error.no_executable")
      case .notExecutable?: reason = OJDLocalized.string("cli.virtual.launch.error.not_executable")
      case .notFound?: reason = OJDLocalized.string("cli.virtual.launch.error.not_found")
      case nil: throw error
      }
      throw Failure.cannotStart(program: program.lastPathComponent, reason: reason)
    }
    let profiles = devices.compactMap { $0.servingDecision.selection?.profileID }
    do {
      let environment = try SDLLaunchEnvironment.environment(
        adding: profiles,
        to: baseEnvironment,
        gameControllerBackend: gameControllerBackend
      )
      return Prepared(executable: executable, environment: environment)
    } catch SDLLaunchEnvironment.Failure.noProfile {
      throw Failure.noGamepad
    }
  }

  /// The profiles among `devices` that SDL does not recognize with its default hints, which the
  /// user can fix by choosing the GameController backend.
  static func profilesNeedingBackend(
    in devices: [ApplicationServiceDeviceDescription]
  ) -> [VirtualHIDProfileID] {
    let profiles = devices.compactMap { $0.servingDecision.selection?.profileID }
    return VirtualHIDProfileID.allCases.filter { profile in
      profiles.contains(profile)
        && ((try? profile.gamepadMapping().worksWithDefaultSDLHints) == false)
    }
  }
}
