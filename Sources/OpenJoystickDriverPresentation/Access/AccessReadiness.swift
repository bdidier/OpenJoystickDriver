import Foundation

struct AccessReadinessStatus: Equatable {
  let value: String
  let tone: SemanticTone
  let isActionable: Bool
}

/// The macOS permissions the app and its service need, as the Access area shows them.
struct AccessReadiness {
  let permissionState: RuntimePermissionLoadState
  let statusState: RuntimeStatusState
  let notificationState: RuntimeNotificationAuthorizationState
  let notificationSettings: RuntimeNotificationSettings

  var inputRead: AccessReadinessStatus { permissionStatus(for: permissionSummary?.inputRead) }

  var inputInject: AccessReadinessStatus { permissionStatus(for: permissionSummary?.inputInject) }

  var postEvent: AccessReadinessStatus {
    guard case .available(let status) = statusState,
      let requiresPostEventAccess = status.requiresPostEventAccess
    else { return Self.checking(isActionable: true) }
    guard requiresPostEventAccess else {
      return AccessReadinessStatus(
        value: OJDLocalized.string("status.notNeeded"),
        tone: .neutral,
        isActionable: false
      )
    }
    switch status.postEventAccess {
    case .granted: return Self.allowed
    case .notAuthorized: return Self.needsAttention
    case nil: return Self.checking(isActionable: true)
    }
  }

  var notification: AccessReadinessStatus {
    switch notificationState {
    case .checking: return Self.checking(isActionable: false)
    case .allowed:
      if notificationSettings.alertStyle == .none {
        return AccessReadinessStatus(
          value: OJDLocalized.string("settings.notificationBannersOff"),
          tone: .caution,
          isActionable: true
        )
      }
      if notificationSettings.soundsEnabled == false {
        return AccessReadinessStatus(
          value: OJDLocalized.string("settings.notificationSoundOff"),
          tone: .caution,
          isActionable: true
        )
      }
      return Self.allowed
    case .notDetermined:
      return AccessReadinessStatus(
        value: OJDLocalized.string("common.notRequested"),
        tone: .caution,
        isActionable: true
      )
    case .denied: return Self.needsAttention
    }
  }

  /// Whether Post Event access must still be requested: the active profile requires it and the
  /// service has not reported it granted.
  static func postEventAccessNeedsRequest(in status: RuntimeStatusPresentation) -> Bool {
    status.requiresPostEventAccess == true && status.postEventAccess != .granted
  }

  /// Whether a permission the service needs is missing: one of the Input Read, Input Inject and
  /// Post Event cards reads Needs attention. The rule is the cards' own, so the status item, the
  /// problem banner and the Access area agree:
  /// - Permissions being read or requested, or not read yet, show Checking and are not missing.
  /// - A permission denied or never requested is missing.
  /// - Post Event access counts only when the active profile requires it and it is not
  ///   authorized.
  /// - A failed permission read shows Needs attention, so the user can retry by granting.
  /// A notification setting never counts.
  static func hasMissingPermission(
    permissionState: RuntimePermissionLoadState,
    statusState: RuntimeStatusState
  ) -> Bool {
    let readiness = Self(
      permissionState: permissionState,
      statusState: statusState,
      notificationState: .checking,
      notificationSettings: .authorizationOnly(.checking)
    )
    return [readiness.inputRead, readiness.inputInject, readiness.postEvent].contains {
      $0.tone == .caution
    }
  }

  /// The four values in card order, for the accessibility value of the group.
  var summaryValue: String {
    [inputRead.value, inputInject.value, postEvent.value, notification.value].joined(
      separator: ", "
    )
  }

  /// Input permissions take effect in a new process, so the app offers a restart while one is
  /// missing.
  var needsRestart: Bool {
    guard let permissionSummary else { return false }
    return permissionSummary.inputRead != .granted || permissionSummary.inputInject != .granted
  }

  /// The permissions as read: the app's own reading, or the service status when the app has not
  /// read them. While a read or request is running, or after it failed, the status holds a
  /// placeholder, so there is no reading.
  private var permissionSummary: RuntimePermissionSummary? {
    switch permissionState {
    case .available(let permissions): return permissions
    case .unavailable:
      if case .available(let status) = statusState { return status.permissions }
      return nil
    case .loading, .requesting, .error: return nil
    }
  }

  private func permissionStatus(for state: RuntimePermissionState?) -> AccessReadinessStatus {
    switch state {
    case .granted: return Self.allowed
    case .denied, .unknown: return Self.needsAttention
    case nil:
      switch permissionState {
      case .loading, .requesting, .unavailable: return Self.checking(isActionable: true)
      case .available, .error: return Self.needsAttention
      }
    }
  }

  private static var allowed: AccessReadinessStatus {
    AccessReadinessStatus(
      value: OJDLocalized.string("status.allowed"),
      tone: .positive,
      isActionable: false
    )
  }

  private static var needsAttention: AccessReadinessStatus {
    AccessReadinessStatus(
      value: OJDLocalized.string("common.needsAttention"),
      tone: .caution,
      isActionable: true
    )
  }

  private static func checking(isActionable: Bool) -> AccessReadinessStatus {
    AccessReadinessStatus(
      value: OJDLocalized.string("status.checking"),
      tone: .neutral,
      isActionable: isActionable
    )
  }
}
