import CoreGraphics
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// Reads and requests the macOS HID permissions through the IOHID access calls.
package struct MacOSAccessControlSystem: AccessControlSystem {
  package init() {}

  package func inputReadAccessState() -> PermissionManager.AccessState {
    Self.accessState(for: kIOHIDRequestTypeListenEvent)
  }

  /// IOHIDUserDevice creation is authorized through the post-event TCC service.
  package func inputInjectAccessState() -> PermissionManager.AccessState {
    Self.accessState(for: kIOHIDRequestTypePostEvent)
  }

  package func postEventAccessState() -> RemappingPostEventAccessState {
    CGPreflightPostEventAccess() ? .granted : .notAuthorized
  }

  @MainActor
  package func requestInputReadAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

  @MainActor
  package func requestInputInjectAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent) }

  private static func accessState(
    for requestType: IOHIDRequestType
  )
    -> PermissionManager.AccessState
  {
    switch IOHIDCheckAccess(requestType) {
    case kIOHIDAccessTypeGranted: return .granted
    case kIOHIDAccessTypeDenied: return .denied
    default: return .unknown
    }
  }
}
