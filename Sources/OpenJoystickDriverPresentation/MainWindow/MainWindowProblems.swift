import Foundation

/// Something that stops controllers from working, shown in the main window's problem banner
/// while it lasts. A healthy app has none, and the banner is then absent.
enum MainWindowProblem: Equatable, Sendable, Identifiable {
  /// The application service did not answer; the message says why.
  case serviceUnavailable(String)
  /// The Xbox USB driver extension is not active.
  case driver(SystemExtensionSetupState)
  /// macOS has not granted a permission the service needs.
  case accessMissing

  var id: String {
    switch self {
    case .serviceUnavailable: return "service"
    case .driver: return "driver"
    case .accessMissing: return "access"
    }
  }

  var titleKey: String {
    switch self {
    case .serviceUnavailable: return "banner.service.title"
    case .driver: return "setup.driverTitle"
    case .accessMissing: return "banner.access.title"
    }
  }

  /// Localization key of the detail, or nil when the detail is the service's own message.
  var detailKey: String? {
    switch self {
    case .serviceUnavailable: return nil
    case .driver(let state):
      switch state {
      case .missingEmbedded: return "setup.missingDetail"
      case .invalid: return "setup.invalidDetail"
      case .awaitingApproval: return "setup.approvalDetail"
      case .needsActivation, .replacementNeeded, .failed: return "setup.repairDetail"
      case .checking, .active:
        preconditionFailure("A driver problem is never made for \(state)")
      }
    case .accessMissing: return "banner.access.detail"
    }
  }

  var action: MainWindowProblemAction? {
    switch self {
    case .serviceUnavailable: return .startService
    case .driver(let state):
      switch state {
      case .awaitingApproval: return .openDriverApproval
      case .needsActivation, .replacementNeeded, .failed, .invalid: return .repairDriver
      case .missingEmbedded: return nil
      case .checking, .active:
        preconditionFailure("A driver problem is never made for \(state)")
      }
    case .accessMissing: return .showAccess
    }
  }

  /// Problems that stop every controller are failures; the rest need the user's attention.
  var isFailure: Bool {
    switch self {
    case .serviceUnavailable: return true
    case .driver(let state): return state == .missingEmbedded || state == .invalid
    case .accessMissing: return false
    }
  }

  /// The problems of the current state, most blocking first: without the service nothing else
  /// can be read, and without the driver Xbox USB controllers cannot connect.
  static func current(
    status: RuntimeStatusState,
    driver: SystemExtensionSetupState
  ) -> [Self] {
    var problems: [Self] = []
    switch status {
    case .unavailable(let message), .error(let message):
      problems.append(.serviceUnavailable(message))
    case .loading, .available: break
    }
    switch driver {
    case .checking, .active: break
    case .missingEmbedded, .needsActivation, .replacementNeeded, .awaitingApproval, .failed,
      .invalid:
      problems.append(.driver(driver))
    }
    if case .available(let presentation) = status, presentation.needsAccess {
      problems.append(.accessMissing)
    }
    return problems
  }
}

enum MainWindowProblemAction: Equatable, Sendable {
  case startService
  case openDriverApproval
  case repairDriver
  case showAccess

  var titleKey: String {
    switch self {
    case .startService: return "banner.service.start"
    case .openDriverApproval: return "setup.openSystemSettings"
    case .repairDriver: return "setup.repairDriver"
    case .showAccess: return "menuBar.grantAccess"
    }
  }
}

extension RuntimeStatusPresentation {
  /// Whether a permission the service needs is missing.
  var needsAccess: Bool {
    let needsPostEventAccess = requiresPostEventAccess == true && postEventAccess != .granted
    return !permissions.isReady || needsPostEventAccess
  }
}
