import Testing

@testable import OpenJoystickDriverKit

/// A test suite that feeds one family's driver input reports and checks the state it decodes.
protocol ParserSuite {
  /// The family whose parser the suite's tests cover.
  static var family: PhysicalProtocolID { get }
  /// A catalog model of that family; the registry builds the driver the suite's tests feed.
  static var model: ControllerModelID { get }
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

  /// A suite's family is the family the registry binds its model to and builds the driver for,
  /// so a suite listed under the wrong family fails.
  @Test(arguments: parserSuites.map { SuiteBox(suite: $0) })
  func eachSuiteCoversTheDriverTheRegistryBuildsForItsFamily(box: SuiteBox) throws {
    let suite = box.suite
    let record = try #require(ProtocolDriverRegistry().record(for: suite.model))
    #expect(record.physicalProtocolID == suite.family, "\(suite)")
    let driver = try catalogParser(suite.model)
    #expect(
      ProtocolDriverRegistryTests.driver(driver, belongsTo: suite.family),
      "\(suite)"
    )
  }

  struct SuiteBox: CustomTestStringConvertible, Sendable {
    nonisolated(unsafe) let suite: any ParserSuite.Type
    var testDescription: String { String(describing: suite) }
  }
}
