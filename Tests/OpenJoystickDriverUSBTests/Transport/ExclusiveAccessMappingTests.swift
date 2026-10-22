import IOKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct ExclusiveAccessMappingTests {
  @Test
  func exclusiveAccessWithAnOwnerNamesTheOwner() {
    let owner = "pid 11070, steam_osx"
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnExclusiveAccess, exclusiveOwner: owner)
        == .ownedByAnotherClient(owner: owner)
    )
  }

  @Test
  func exclusiveAccessWithoutAnOwnerCarriesNone() {
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnExclusiveAccess, exclusiveOwner: nil)
        == .ownedByAnotherClient(owner: nil)
    )
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnExclusiveAccess)
        == .ownedByAnotherClient(owner: nil)
    )
  }

  @Test
  func notPermittedStaysAccessDeniedWithoutTheOwner() {
    let owner = "pid 1, ignored"
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnNotPermitted, exclusiveOwner: owner)
        == .accessDenied
    )
  }

  @Test
  func notPrivilegedStaysAccessDeniedWithoutTheOwner() {
    let owner = "pid 1, ignored"
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnNotPrivileged, exclusiveOwner: owner)
        == .accessDenied
    )
  }
}
