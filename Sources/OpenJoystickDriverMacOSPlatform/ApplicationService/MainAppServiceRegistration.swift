import Foundation
import OpenJoystickDriverKit
import ServiceManagement

/// The main application's login-item registration through `SMAppService`.
package struct MainAppServiceRegistration: ApplicationServiceRegistration {
  package init() {}

  package var status: ApplicationServiceRegistrationStatus {
    guard #available(macOS 13.0, *) else { return .notFound }
    switch SMAppService.mainApp.status {
    case .notRegistered: return .notRegistered
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notFound: return .notFound
    @unknown default: return .notFound
    }
  }

  package func register() throws {
    guard #available(macOS 13.0, *) else {
      throw ApplicationServiceManager.ManagerError.unsupportedOperatingSystem
    }
    try SMAppService.mainApp.register()
  }

  package func unregister() throws {
    guard #available(macOS 13.0, *) else {
      throw ApplicationServiceManager.ManagerError.unsupportedOperatingSystem
    }
    try SMAppService.mainApp.unregister()
  }
}
