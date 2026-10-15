import Foundation
import OpenJoystickDriverKit

/// Stable failures from the locally persisted remapping-profile library.
enum RemappingProfileLibraryError: Error, Equatable, LocalizedError, Sendable {
  case corruptLibrary
  case duplicateName(String)
  case invalidProfile(RemappingValidationError)
  case profileCountExceeded(Int)
  case profileAlreadyExists(UUID)
  case profileNotFound(UUID)
  case pairProfileRequiresExplicitSession
  case profileProducesNoOutput(UUID)
  case profileUpdateConflict(UUID)
  case unreadableLibrary
  case unwritableLibrary
  case profileRecoveryRequired
  case profileIssueNotFound(UUID)
  case packageProfileReadOnly

  var errorDescription: String? {
    switch self {
    case .corruptLibrary: "The active remapping profile list is damaged."
    case .duplicateName(let name): "A remapping profile named \(name) already exists."
    case .invalidProfile(let error): error.localizedDescription
    case .profileCountExceeded(let count): "There cannot be \(count) remapping profiles."
    case .profileAlreadyExists(let id): "The remapping profile \(id.uuidString) already exists."
    case .profileNotFound(let id): "The remapping profile \(id.uuidString) does not exist."
    case .pairProfileRequiresExplicitSession:
      "Paired Joy-Con profiles are started with an explicit pair session."
    case .profileProducesNoOutput(let id):
      "The remapping profile \(id.uuidString) produces no output; activating it needs "
        + "allowEmpty."
    case .profileUpdateConflict(let id):
      "The remapping profile \(id.uuidString) changed since it was read."
    case .unreadableLibrary: "A remapping profile file could not be read."
    case .unwritableLibrary: "A remapping profile file could not be written."
    case .profileRecoveryRequired:
      "Repair or remove the damaged profile files before changing profiles."
    case .profileIssueNotFound: "The selected damaged profile is no longer current."
    case .packageProfileReadOnly:
      "A profile that comes from an installed package cannot be changed. Duplicate the profile "
        + "and change the copy."
    }
  }
}

/// The single application-service writer for locally authored remapping profiles.
///
/// Each profile is its own `Profiles/<id>.json` file in the profile-file format, and the active
/// selections are `ActiveProfiles.json`, both under `directory`. The profiles of the installed
/// packages in `Packages/` are served read-only beside them; they are never written, counted
/// against the profile limit, or deleted.
actor RemappingProfileLibrary {
  static let maximumProfileCount = RemappingPayloadLimits.maximumProfileCount
  static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes
  static let selectionsFileName = "ActiveProfiles.json"
  static let legacyLibraryFileName = "RemappingProfiles.json"

  let directory: URL
  var library: RemappingProfileLibraryState?
  var profileIssues: [UUID: RecoveryIssue] = [:]
  /// The profiles of the installed packages, read with the library and never written.
  var packageProfiles: [PackageProfile] = []
  /// The OJD version that the `requires` of a package is checked against; nil for the running one.
  let runningVersion: String?

  init(directory: URL = RemappingProfileLibrary.defaultDirectory, runningVersion: String? = nil) {
    self.directory = directory
    self.runningVersion = runningVersion
  }

  static var defaultDirectory: URL { MacOSDataDirectory().url(for: .applicationData) }

  nonisolated var profilesDirectory: URL {
    directory.appendingPathComponent("Profiles", isDirectory: true)
  }

  nonisolated var selectionsURL: URL {
    directory.appendingPathComponent(Self.selectionsFileName, isDirectory: false)
  }

  nonisolated func profileURL(_ id: UUID) -> URL {
    profilesDirectory.appendingPathComponent(Self.profileFileName(id), isDirectory: false)
  }

  static func profileFileName(_ id: UUID) -> String { "\(id.uuidString).json" }
}
