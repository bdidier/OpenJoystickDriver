@testable import OpenJoystickDriverKit

extension ProtocolBindingResult {
  /// A `HIDDescriptor` binding with no observed interfaces, for descriptions whose binding
  /// decision a test does not examine.
  package static let hidDescriptorFixture = ProtocolBindingResult(
    binding: ProtocolBinding(
      protocolID: .hidDescriptor,
      variant: nil,
      accessBackend: .hid,
      interfaceNumber: nil,
      rule: .hidDescriptor,
      matchedPredicates: [.hidDescriptorContract],
      record: nil
    ),
    interfaces: []
  )
}
