import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

extension ControllerSessionTests {
  /// A USB DualShock 3 that has sent no input since its session started waits for a press of its
  /// PS button; once it has sent input, a silence is missing reports again.
  @Test
  func aSixaxisWithNoInputYetWaitsForAGuidePress() async throws {
    let identifier = LogicalControllerID(vendorID: 0x054C, productID: 0x0268)
    let clock = ManualUptime()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: SixaxisDriver(),
      dispatcher: ControllerSessionOutputProbe(),
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    clock.advance(by: 1_100_000_000)
    await pipeline.evaluateIdleSleep()
    #expect(await pipeline.inputHealth().failureReason == .guideNotPressed)

    await pipeline.feedHIDData(ProtocolPacketFixtures.DS3.inputReport())
    #expect(await pipeline.inputHealth().state == .healthy)
    clock.advance(by: 1_100_000_000)
    await pipeline.evaluateIdleSleep()
    #expect(await pipeline.inputHealth().failureReason == .missingReports)
    await pipeline.stop()
  }
}
