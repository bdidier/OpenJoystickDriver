import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct AccessReadinessTests {
  private func readiness(
    permissions: RuntimePermissionLoadState,
    notification: RuntimeNotificationAuthorizationState = .allowed,
    settings: RuntimeNotificationSettings? = nil
  ) -> AccessReadiness {
    AccessReadiness(
      permissionState: permissions,
      statusState: .loading,
      notificationState: notification,
      notificationSettings: settings ?? .authorizationOnly(notification)
    )
  }

  @Test
  func grantedInputPermissionsNeedNoRestart() {
    let value = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .granted, inputInject: .granted))
    )

    #expect(value.inputRead.tone == .positive)
    #expect(!value.inputRead.isActionable)
    #expect(!value.needsRestart)
  }

  @Test
  func aDeniedInputPermissionIsActionableAndOffersARestart() {
    let value = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .denied, inputInject: .granted))
    )

    #expect(value.inputRead.tone == .caution)
    #expect(value.inputRead.isActionable)
    #expect(value.inputInject.tone == .positive)
    #expect(value.needsRestart)
  }

  @Test
  func permissionsStillLoadingAreChecking() {
    let value = readiness(permissions: .loading)

    #expect(value.inputRead.tone == .neutral)
    #expect(value.inputRead.value == OJDLocalized.string("status.checking"))
    #expect(!value.needsRestart)
  }

  @Test
  func postEventAccessIsCheckingUntilTheStatusArrives() {
    let value = readiness(permissions: .unavailable)

    #expect(value.postEvent.value == OJDLocalized.string("status.checking"))
    #expect(value.postEvent.isActionable)
  }

  @Test
  func notificationsWithBannersOffNeedAttention() {
    let value = readiness(
      permissions: .unavailable,
      settings: RuntimeNotificationSettings(
        authorization: .allowed,
        alertStyle: .none,
        soundsEnabled: true
      )
    )

    #expect(value.notification.value == OJDLocalized.string("settings.notificationBannersOff"))
    #expect(value.notification.isActionable)
  }

  @Test
  func notificationsAllowedWithBannersAndSoundAreReady() {
    let value = readiness(
      permissions: .unavailable,
      settings: RuntimeNotificationSettings(
        authorization: .allowed,
        alertStyle: .banner,
        soundsEnabled: true
      )
    )

    #expect(value.notification.tone == .positive)
    #expect(!value.notification.isActionable)
  }

  @Test
  func notificationsNotYetRequestedAreActionable() {
    let value = readiness(permissions: .unavailable, notification: .notDetermined)

    #expect(value.notification.value == OJDLocalized.string("common.notRequested"))
    #expect(value.notification.isActionable)
  }

  private func status(
    postEvent: RemappingPostEventAccessState?,
    requiresPostEvent: Bool?,
    inputRead: PermissionManager.AccessState = .granted
  ) -> RuntimeStatusState {
    .available(
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: inputRead,
          inputInject: .granted,
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready")
        ),
        postEventAccess: postEvent,
        requiresPostEventAccess: requiresPostEvent
      )
    )
  }

  @Test
  func noPermissionIsMissingWhenAllAreGrantedOrNothingWasRead() {
    let granted = RuntimePermissionLoadState.available(
      RuntimePermissionSummary(inputRead: .granted, inputInject: .granted)
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: granted,
        statusState: status(postEvent: .granted, requiresPostEvent: true)
      )
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: granted,
        statusState: status(postEvent: nil, requiresPostEvent: false)
      )
    )
    #expect(
      !AccessReadiness.hasMissingPermission(permissionState: .unavailable, statusState: .loading)
    )
    #expect(!AccessReadiness.hasMissingPermission(permissionState: .loading, statusState: .loading))
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: .unavailable,
        statusState: .unavailable("down")
      )
    )
  }

  @Test
  func theAppsOwnPermissionReadingDecidesOverTheStatusPayload() {
    let granted = RuntimePermissionLoadState.available(
      RuntimePermissionSummary(inputRead: .granted, inputInject: .granted)
    )
    #expect(
      !AccessReadiness.hasMissingPermission(
        permissionState: granted,
        statusState: status(postEvent: .granted, requiresPostEvent: false, inputRead: .denied)
      )
    )
  }

  @Test
  func aDeniedUnknownOrUnauthorizedPermissionIsMissing() {
    func summary(
      _ read: RuntimePermissionState,
      _ inject: RuntimePermissionState
    )
      -> RuntimePermissionLoadState
    {
      .available(RuntimePermissionSummary(inputRead: read, inputInject: inject))
    }
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: summary(.denied, .granted),
        statusState: .loading
      )
    )
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: summary(.granted, .unknown),
        statusState: .loading
      )
    )
    #expect(
      AccessReadiness.hasMissingPermission(
        permissionState: summary(.granted, .granted),
        statusState: status(postEvent: .notAuthorized, requiresPostEvent: true)
      )
    )
  }
}
