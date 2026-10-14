import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDProfileDiscoveryTests {
  @Test
  func hidAndRawUSBCatalogPartitionsAreDisjoint() {
    let registry = ProtocolDriverRegistry()
    let hid = Set(registry.hidModels)
    let rawUSB = Set(registry.rawUSBModels)

    #expect(!hid.isEmpty)
    #expect(!rawUSB.isEmpty)
    #expect(hid.isDisjoint(with: rawUSB))
  }
}
