import Foundation
import Testing

@testable import OpenJoystickDriverKit

// swiftlint:disable:next convenience_type
struct GIPDriverTests {
  static let family = PhysicalProtocolID.xboxGIP
  static let model = ControllerModelID(vendorID: 0x045E, productID: 0x02D1)
}
