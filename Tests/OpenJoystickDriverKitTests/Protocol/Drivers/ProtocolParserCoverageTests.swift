import Testing

@testable import OpenJoystickDriverKit

/// Names, for every physical protocol family, the suite whose tests feed the family's driver an
/// input report and check the state it decodes. A family without an entry fails the test, so a
/// new family cannot ship without a parser test.
struct ProtocolParserCoverageTests {
  static let parserSuites: [PhysicalProtocolID: Any.Type] = [
    .hidDescriptor: HIDDescriptorDriverTests.self,
    .hidReportLayout: ReportLayoutDriverTests.self,
    .xboxXID: XIDDriverTests.self,
    .xboxXUSB: XUSBDriverTests.self,
    .xboxGIP: GIPDriverTests.self,
    .sonySixaxis: SixaxisDriverTests.self,
    .sonyDualShock4: DualShock4DriverTests.self,
    .sonyDualSense: DualSenseDriverTests.self,
    .nintendoSwitch1: Switch1DriverTests.self,
    .nintendoSwitch2: Switch2DriverTests.self,
    .nintendoSwitchInputOnly: SwitchInputOnlyDriverTests.self,
    .valveSteamController: SteamControllerDriverTests.self,
    .valveSteamTriton: SteamTritonDriverTests.self,
    .valveSteamDeck: SteamDeckDriverTests.self,
    .vendorFlydigi: FlydigiDriverTests.self,
    .vendorPS3ThirdParty: PS3ThirdPartyDriverTests.self,
    .vendorGameSir: GameSirDriverTests.self,
    .vendorNVIDIAShield: NVIDIAShieldDriverTests.self,
  ]

  @Test
  func everyProtocolFamilyHasAParserSuite() {
    #expect(Set(Self.parserSuites.keys) == Set(PhysicalProtocolID.allCases))
  }
}
