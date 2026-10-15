import Foundation
import OpenJoystickDriverKit
import Testing

@Suite("Permission inventory")
struct PermissionInventoryTests {
  @Test("Input inject has the same app owner")
  func inputInjectHasOneAppOwner() {
    let inputInject = OJDPermissionRequirement.inventory.filter { $0.name == "Input inject" }
    #expect(inputInject.count == 1)
    #expect(inputInject.first?.requested == true)
    #expect(inputInject.first?.owner == "OpenJoystickDriver app")
  }

  @Test("Input read has one app owner")
  func inputReadHasOneAppOwner() {
    let owners = Set(
      OJDPermissionRequirement.inventory.filter { $0.name == "Input read" && $0.requested }
        .map(\.owner)
    )
    #expect(owners == ["OpenJoystickDriver app"])
  }

}
