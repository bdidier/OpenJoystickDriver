import Testing

@testable import OpenJoystickDriverKit

/// A test suite that feeds one family's driver input reports and checks the state it decodes.
protocol ParserSuite {
  /// The family whose parser the suite's tests cover.
  static var family: PhysicalProtocolID { get }
}

extension HIDDescriptorDriverTests: ParserSuite {}
extension ReportLayoutDriverTests: ParserSuite {}
extension XIDDriverTests: ParserSuite {}
extension XUSBDriverTests: ParserSuite {}
extension GIPDriverTests: ParserSuite {}
extension SixaxisDriverTests: ParserSuite {}
extension DualShock4DriverTests: ParserSuite {}
extension DualSenseDriverTests: ParserSuite {}
extension Switch1DriverTests: ParserSuite {}
extension Switch2DriverTests: ParserSuite {}
extension SwitchInputOnlyDriverTests: ParserSuite {}
extension SteamControllerDriverTests: ParserSuite {}
extension SteamTritonDriverTests: ParserSuite {}
extension SteamDeckDriverTests: ParserSuite {}
extension FlydigiDriverTests: ParserSuite {}
extension PS3ThirdPartyDriverTests: ParserSuite {}
extension GameSirDriverTests: ParserSuite {}
extension NVIDIAShieldDriverTests: ParserSuite {}

/// Every physical protocol family has a parser suite that declares the family it covers, and no
/// two suites claim the same family, so a new family cannot ship without a parser test.
struct ProtocolParserCoverageTests {
  static let parserSuites: [any ParserSuite.Type] = [
    HIDDescriptorDriverTests.self, ReportLayoutDriverTests.self, XIDDriverTests.self,
    XUSBDriverTests.self, GIPDriverTests.self, SixaxisDriverTests.self,
    DualShock4DriverTests.self, DualSenseDriverTests.self, Switch1DriverTests.self,
    Switch2DriverTests.self, SwitchInputOnlyDriverTests.self, SteamControllerDriverTests.self,
    SteamTritonDriverTests.self, SteamDeckDriverTests.self, FlydigiDriverTests.self,
    PS3ThirdPartyDriverTests.self, GameSirDriverTests.self, NVIDIAShieldDriverTests.self,
  ]

  @Test
  func everyProtocolFamilyHasExactlyOneParserSuite() {
    let families = Self.parserSuites.map { $0.family.rawValue }.sorted()
    #expect(families == PhysicalProtocolID.allCases.map(\.rawValue).sorted())
  }
}
