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
  /// The application's name when `resolveName` finds the bundle identifier, else the identifier;
  /// nil for a profile that applies to every application.
  static func text(
    for scope: RemappingApplicationScope,
    resolveName: (String) -> String? = applicationName
  ) -> String? {
    switch scope {
    case .global: return nil
    case .application(let appID): return resolveName(appID) ?? appID
    }
  }

  /// The installed application's display name for a bundle identifier.
  static func applicationName(_ bundleIdentifier: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    else { return nil }
    return FileManager.default.displayName(atPath: url.path)
  }
}
