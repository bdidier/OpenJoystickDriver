/// Stable local RPC method names; each raw value is the method name on the wire.
package enum ApplicationServiceRPCMethod: String, CaseIterable, Sendable {
  case getStatus
  case requestRequiredAccess
  case requestAccess
  case getControllerState
  case getPacketLog
  case getVirtualOutputState
  case sendControllerOutput
  case previewPhysicalColor
  case releasePhysicalColorPreview
  case getVirtualDeviceDiagnostics
  case getFrameTimings
  case waitForServiceStatusChange
  case sendTestNotification
  case reportTestNotificationResult
  case setVirtualHIDProfileOverride
  case resetVirtualHIDProfileOverride
  case setControllerServer
  case openVirtualFeed
  case exchangeVirtualFeed
  case closeVirtualFeed
  case suspendController
  case resumeController
  case disconnectWirelessController
  case resetSettings
  case getSettings
  case setSetting
  case getAccessStatus
  case setAccessEnabled
  case grantAccess
  case revokeAccess
  case grantTokenAccess
  case setWebAccess
  case remappingMotionCalibration
  case pairRemappingJoyCons
  case unpairRemappingJoyCons
  case getRemappingSnapshot
  case getRemappingProfile
  case createRemappingProfile
  case updateRemappingProfile
  case deleteRemappingProfile
  case importRemappingProfile
  case activateRemappingProfile
  case deactivateRemappingProfile
  case deactivateRemappingProfileByID
  case getRemappingPostEventAccess
  case requestRemappingPostEventAccess
  case deleteDamagedRemappingProfile
  case resetRemappingProfileLibrary

  /// True for a method whose reply stays open until something happens, so the server cancels it
  /// when its client closes the connection: the status wait, which is held up to the hold time,
  /// and the test notification request, which waits for the app's report. Every other method
  /// runs to completion even if the client has left, because it changes state or asks the
  /// system for something that must not stop halfway.
  var holdsReplyOpen: Bool {
    switch self {
    case .waitForServiceStatusChange, .sendTestNotification: true
    default: false
    }
  }
}
