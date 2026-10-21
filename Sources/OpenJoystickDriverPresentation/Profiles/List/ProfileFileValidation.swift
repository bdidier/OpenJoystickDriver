import AppKit
import Foundation
import OpenJoystickDriverKit

/// The result of checking a profile file without adding it, the check `ojd profile validate`
/// runs: a valid profile with what it targets, or the problem with its error code.
enum ProfileFileValidation: Equatable, Identifiable {
  case valid(name: String, controller: String, scope: String)
  case invalid(fileName: String, code: String, problem: String)

  /// Checks the contents of the file named `fileName` with the loader that import and the CLI use.
  static func check(_ data: Data, fileName: String) -> Self {
    do {
      let profile = try RemappingProfileFileStore.load(from: data)
      let scope: String
      switch profile.applicationScope {
      case .global: scope = RuntimePresentation.profileScopeLabel(.global)
      case .application(let appID): scope = appID
      }
      return .valid(
        name: profile.name,
        controller: OJDValue.usbIdentifier(
          vendorID: profile.device.vendorID,
          productID: profile.device.productID
        ).displayText,
        scope: scope
      )
    } catch {
      return .invalid(
        fileName: fileName,
        code: RemappingProfileFileStore.problemCode(error).rawValue,
        problem: DocumentProblem.describe(error)
      )
    }
  }

  var id: String { title + message }

  var title: String {
    switch self {
    case .valid: return OJDLocalized.string("profiles.validTitle")
    case .invalid: return OJDLocalized.string("profiles.invalidTitle")
    }
  }

  var message: String {
    switch self {
    case .valid(let name, let controller, let scope):
      return OJDLocalized.formatted("profiles.validMessage", name, controller, scope)
    case .invalid(let fileName, let code, let problem):
      return OJDLocalized.formatted(
        "error.withCode",
        OJDLocalized.formatted("cli.profile.document_invalid", fileName, problem),
        code
      )
    }
  }
}

/// How the Profiles list names the application a profile is limited to.
enum ProfileScopeCaption {
  /// The caption under a profile's name: the assignment count for a profile that applies to every
  /// application, else the application's name (the identifier when `resolveName` does not find
  /// it) and the count.
  static func text(
    for scope: RemappingApplicationScope,
    assignments: String,
    resolveName: (String) -> String?
  ) -> String {
    switch scope {
    case .global: return assignments
    case .application(let appID):
      return OJDLocalized.formatted(
        "profiles.scopedCaption",
        resolveName(appID) ?? appID,
        assignments
      )
    }
  }
}

/// The installed applications' names by bundle identifier. Each identifier is looked up once per
/// session, so the list does not ask LaunchServices again on every redraw.
@MainActor
final class ProfileApplicationNames {
  private var names: [String: String?] = [:]

  func name(for bundleIdentifier: String) -> String? {
    if let known = names[bundleIdentifier] { return known }
    let name = Self.lookUp(bundleIdentifier)
    names[bundleIdentifier] = .some(name)
    return name
  }

  private static func lookUp(_ bundleIdentifier: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return FileManager.default.displayName(atPath: url.path)
  }
}
