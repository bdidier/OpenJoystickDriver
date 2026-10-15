import Testing

@testable import OpenJoystickDriverKit

/// HID discovery reads the endpoint set from the `IOUSBHostPipe` children of the device's
/// `IOUSBHostInterface`. The registry walk needs hardware, so these tests feed the property
/// mapping the dictionaries the registry publishes.
struct HIDEndpointDiscoveryTests {
  private static func pipe(_ address: Int, attributes: Int, size: Int = 64) -> [String: Any] {
    [
      "bEndpointAddress": address, "bmAttributes": attributes, "wMaxPacketSize": size,
      "bInterval": 4,
    ]
  }

  @Test
  func pipePropertiesMapToEndpointSignatures() throws {
    let endpoints = try #require(
      HIDDeviceStream.endpoints(
        fromPipeProperties: [Self.pipe(0x81, attributes: 3), Self.pipe(0x02, attributes: 2)],
        declaredCount: 2
      )
    )
    #expect(
      endpoints == [
        PhysicalEndpointSignature(
          address: 0x81,
          direction: .in,
          transferType: .interrupt,
          maxPacketSize: 64,
          interval: 4
        ),
        PhysicalEndpointSignature(
          address: 0x02,
          direction: .out,
          transferType: .bulk,
          maxPacketSize: 64,
          interval: 4
        ),
      ]
    )
  }

  /// A partial or malformed set must not match an endpoint set, so each reads as unknown.
  @Test
  func anIncompleteSetReportsNoEndpoints() {
    let cases: [(pipes: [[String: Any]], declared: Int)] = [
      ([Self.pipe(0x81, attributes: 3)], 2),
      ([Self.pipe(0x81, attributes: 3), Self.pipe(0x81, attributes: 3)], 2),
      ([["bEndpointAddress": 0x81]], 1),
      ([Self.pipe(0x81, attributes: 3)], -1),
    ]
    for item in cases {
      #expect(
        HIDDeviceStream.endpoints(fromPipeProperties: item.pipes, declaredCount: item.declared)
          == nil
      )
    }
  }

  @Test
  func anUnknownDeclaredCountReportsNoEndpoints() {
    #expect(
      HIDDeviceStream.endpoints(
        fromPipeProperties: [Self.pipe(0x81, attributes: 3)],
        declaredCount: nil
      ) == nil
    )
  }

  /// Bluetooth HID has no USB interface: it reports no endpoints, so no endpoints key matches.
  @Test
  func anInterfaceWithoutEndpointsNeverMatchesAnEndpointsKey() {
    let match = ControllerModeMatch.InterfaceSignature(
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      usagePage: nil,
      usage: nil,
      endpoints: [.init(direction: .in, transferType: .interrupt)]
    )
    let bluetooth = PhysicalInterfaceSignature(
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      hostTransport: .bluetoothClassic
    )
    let usb = PhysicalInterfaceSignature(
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      hostTransport: .usb,
      endpoints: [PhysicalEndpointSignature(direction: .in, transferType: .interrupt)]
    )
    #expect(!match.matches(bluetooth))
    #expect(match.matches(usb))
  }
}
