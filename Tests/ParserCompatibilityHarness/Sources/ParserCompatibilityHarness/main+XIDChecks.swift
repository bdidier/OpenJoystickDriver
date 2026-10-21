import Foundation
import OpenJoystickDriverKit

func runXIDInputChecks() throws {
  let profile = catalogRecord(ControllerModelID(vendorID: 0x045E, productID: 0x0202))
  require(
    profile.physicalProtocolID == .xboxXID && profile.physicalProtocolVariant == .gamepad,
    "Original Xbox pad should bind XID"
  )

  let parser = xidDriver()
  _ = try parse(parser, makeXIDReport())
  let analog = try parse(parser, makeXIDReport(analogA: 0xFF))
  require(
    analog?.pressed.contains(.south) == true,
    "XID analog A should become a digital press"
  )
  let digital = try parse(parser, makeXIDReport(digital: 0x11))
  require(digital?.pressed.contains(.start) == true, "XID digital start should parse")
  require(digital?.hat == .north, "XID digital d-pad north should parse")
}

func xidDriver() -> ReportLayoutDriver {
  ReportLayoutDriver(
    describedBy: .xboxXID,
    variant: .gamepad,
    rumbleTemplate: nil,
    outEndpoint: 0x02,
    tuning: nil
  )
}

func makeXIDReport(digital: UInt8 = 0, analogA: UInt8 = 0) -> Data {
  var report = [UInt8](repeating: 0, count: 20)
  report[1] = 0x14
  report[2] = digital
  report[4] = analogA
  return Data(report)
}
