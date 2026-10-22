#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestView {

    var statusLabel: String {
      switch model.sessionState {
      case .idle: return OJDLocalized.string("ui.inputTest.idle")
      case .starting: return OJDLocalized.string("ui.inputTest.starting")
      case .live: return OJDLocalized.string("ui.inputTest.live")
      case .stale: return OJDLocalized.string("ui.inputTest.stale")
      case .disconnected:
        return OJDLocalized.string("ui.inputTest.disconnected")
      case .permissionRequired:
        return OJDLocalized.string(
          "platform.macos.ui.inputTest.permissionRequired"
        )
      case .unavailable:
        return OJDLocalized.string("ui.inputTest.unavailable")
      case .error: return OJDLocalized.string("status.failed")
      }
    }

    var statusSemanticState: SemanticState {
      switch model.sessionState {
      case .live: return .active
      case .starting: return .loading
      case .stale, .permissionRequired: return .attention
      case .idle: return .inactive
      case .disconnected: return .disconnected
      case .unavailable: return .unknown
      case .error: return .failure
      }
    }

    func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
      .usbIdentifier(vendorID: device.vendorID, productID: device.productID)
    }
  }

#endif
