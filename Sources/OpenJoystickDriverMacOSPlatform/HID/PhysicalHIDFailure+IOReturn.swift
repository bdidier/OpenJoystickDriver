import IOKit
import OpenJoystickDriverKit

extension PhysicalHIDFailure {
  /// `kIOUSBPipeStalled`: the device answered a control request with a STALL.
  private static let pipeStalled = IOReturn(bitPattern: 0xE000_404F)

  /// The failure an IOKit status code stands for. A device's own refusal (a stalled pipe or an
  /// unsupported request) is `declined`; a code without a name stays `hostStatus`.
  init(ioReturn code: IOReturn) {
    switch code {
    case kIOReturnTimeout: self = .timedOut
    case kIOReturnBusy: self = .busy
    case kIOReturnNotResponding: self = .notResponding
    case Self.pipeStalled, kIOReturnUnsupported: self = .declined
    default: self = .hostStatus(code)
    }
  }
}
