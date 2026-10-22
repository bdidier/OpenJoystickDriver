import Foundation
import OpenJoystickDriverKit

struct SupportDiagnosticsPresentation: Sendable, Equatable {
  enum VirtualControllerOutputState: String, Sendable, Equatable {
    case available
    case unavailable
    case needsAttention
  }

  let virtualControllerOutputState: VirtualControllerOutputState
  let virtualControllerCount: Int

  init(payload: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    self.init(diagnostics: payload)
  }

  init(diagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload) {
    if diagnostics.userSpaceVirtualDeviceStatus.isError {
      virtualControllerOutputState = .needsAttention
    } else if diagnostics.userSpaceVirtualDeviceEnabled {
      virtualControllerOutputState = .available
    } else {
      virtualControllerOutputState = .unavailable
    }
    virtualControllerCount = diagnostics.hidGamepads.count(where: \.isOJDUserSpace)
  }

  var virtualControllerOutputLabel: String {
    switch virtualControllerOutputState {
    case .available: return OJDLocalized.string("status.available")
    case .unavailable: return OJDLocalized.string("status.unavailable")
    case .needsAttention:
      return OJDLocalized.string("status.needsAttention")
    }
  }

  var virtualControllerOutputDetail: String {
    switch virtualControllerOutputState {
    case .available:
      return OJDLocalized.string(
        "ui.debug.outputAvailable"
      )
    case .unavailable:
      return OJDLocalized.string("ui.debug.outputOff")
    case .needsAttention:
      return OJDLocalized.string(
        "ui.debug.outputNeedsAttention"
      )
    }
  }

  var virtualControllerCountLabel: String {
    OJDLocalized.plural(
      "ui.debug.outputDevices",
      count: virtualControllerCount
    )
  }
}

enum RuntimeSupportDiagnosticsState: Sendable {
  case idle
  case loading
  case available(SupportDiagnosticsPresentation)
  case unavailable(String)
  case error(String)
}

enum RuntimeSupportReportState: Sendable {
  case idle
  case saving
  case saved
  case error(String)
}

enum RuntimeSupportLogsState: Sendable {
  case idle
  case saving
  case saved
  case error(String)
}
