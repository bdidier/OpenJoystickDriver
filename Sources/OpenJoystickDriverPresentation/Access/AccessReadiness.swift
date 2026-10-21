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

  /// Whether a permission the service needs is missing: denied or never requested, or Post Event
  /// access required and not authorized. Permissions that were never read, a value still being
  /// checked and a notification setting do not count. Reads the same sources as the Access area,
  /// so the status item and the area agree.
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
    let postEventIsMissing = readiness.postEvent.tone == .caution
    guard let summary = readiness.permissionSummary else { return postEventIsMissing }
    return !summary.isReady || postEventIsMissing
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

  private var permissionSummary: RuntimePermissionSummary? {
    if case .available(let permissions) = permissionState { return permissions }
    if case .available(let status) = statusState { return status.permissions }
    return nil
  }

  private func permissionStatus(for state: RuntimePermissionState?) -> AccessReadinessStatus {
    switch state {
    case .granted: return Self.allowed
    case .denied, .unknown: return Self.needsAttention
    case nil:
      switch permissionState {
      case .loading, .requesting: return Self.checking(isActionable: true)
      case .available, .unavailable, .error: return Self.needsAttention
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
