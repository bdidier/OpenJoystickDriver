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

  @Test
  func allowedPermissionsHaveNoButton() {
    let value = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .granted, inputInject: .granted))
    )

    #expect(value.rows.filter { $0.kind != .postEvent }.allSatisfy { $0.actionTitleKey == nil })
  }

  @Test
  func aMissingPermissionOffersSystemSettingsAndANotRequestedOneAsksFirst() {
    let denied = readiness(
      permissions: .available(RuntimePermissionSummary(inputRead: .denied, inputInject: .granted))
    )
    let notRequested = readiness(permissions: .unavailable, notification: .notDetermined)

    #expect(
      denied.rows.first { $0.kind == .inputRead }?.actionTitleKey == "setup.openSystemSettings"
    )
    #expect(denied.rows.first { $0.kind == .inputInject }?.actionTitleKey == nil)
    #expect(
      notRequested.rows.first { $0.kind == .notification }?.actionTitleKey == "common.request"
    )
  }

  @Test
  func aCheckingPermissionHasNoButton() {
    let value = readiness(permissions: .loading)

    #expect(value.rows.first { $0.kind == .inputRead }?.actionTitleKey == nil)
  }

  @Test
  func aPostEventPermissionThatIsNotNeededHasNoRow() {
    let notNeeded = AccessReadiness(
      permissionState: .loading,
      statusState: .available(
        RuntimeStatusPresentation(
          payload: ApplicationServiceStatusPayload(
            inputRead: .granted,
            inputInject: .granted,
            connectedDevices: [],
            userSpaceVirtualDeviceEnabled: true,
            userSpaceVirtualDeviceStatus: .backend("ready")
          ),
          requiresPostEventAccess: false
        )
      ),
      notificationState: .allowed,
      notificationSettings: .authorizationOnly(.allowed)
    )

    #expect(
      notNeeded.rows.map { $0.kind } == [
        AccessPermissionRow.Kind.inputRead, .inputInject, .notification,
      ]
    )
    #expect(
      readiness(permissions: .loading).rows.map { $0.kind }
        == [AccessPermissionRow.Kind.inputRead, .inputInject, .postEvent, .notification]
    )
  }
}
