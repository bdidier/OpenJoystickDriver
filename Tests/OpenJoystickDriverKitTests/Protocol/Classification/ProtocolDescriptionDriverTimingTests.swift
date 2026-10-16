import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Each family timing a driver reads comes from the family's description, and a record's tuning
/// overrides it.
@Suite
struct ProtocolDescriptionDriverTimingTests {
  private static let millisecond = DeviceTransportProfile.nanosecondsPerMillisecond

  @Test
  func steamTritonReadsTheLizardResend() {
    #expect(SteamTritonDriver().lizardResendTicks == 75)
    #expect(SteamTritonDriver(tuning: .init(lizardResendTicks: 9)).lizardResendTicks == 9)
  }

  @Test
  func switch2ReadsTheCommandTimeout() {
    #expect(Switch2Driver().commandTimeoutMilliseconds == 1_000)
    let tuned = Switch2Driver(tuning: .init(usbCommandTimeoutMilliseconds: 250))
    #expect(tuned.commandTimeoutMilliseconds == 250)
    guard case .usb(let packet, _) = tuned.command([0, 0, 0]) else {
      Issue.record("a Switch 2 command is a USB write")
      return
    }
    #expect(packet.timeoutMilliseconds == 250)
  }

  @Test
  func gameSirReadsTheUSBTimeout() {
    #expect(GameSirDriver(protocol: .g7ProUSB).usbTimeoutMilliseconds == 2_000)
    let tuned = GameSirDriver(
      protocol: .g7ProUSB,
      tuning: .init(usbCommandTimeoutMilliseconds: 300)
    )
    #expect(tuned.usbTimeoutMilliseconds == 300)
  }

  @Test
  func gipReadsTheAnnounceResendAndTheHandshakePacing() {
    let driver = GIPDriver()
    #expect(driver.announceResendInterval == 4)
    #expect(driver.sessionPlan.usbStartupIntervalNanoseconds == 50 * Self.millisecond)
    #expect(
      driver.sessionPlan.usbStartupRetryDelays == [
        1_000 * Self.millisecond, 2_000 * Self.millisecond,
      ]
    )
    let tuning = ControllerTuning(
      presenceResendReports: 6,
      usbStartupIntervalMilliseconds: 10,
      usbStartupRetryDelayMilliseconds: 100
    )
    #expect(GIPDriver(tuning: tuning).announceResendInterval == 6)
    let plan = driver.sessionPlan.tuned(tuning)
    #expect(plan.usbStartupIntervalNanoseconds == 10 * Self.millisecond)
    #expect(plan.usbStartupRetryDelays == [100 * Self.millisecond, 200 * Self.millisecond])
  }

  @Test
  func gipReadsTheHandshakeAttemptsAndTheAnnounceResendLimit() {
    let description = PhysicalProtocolID.xboxGIP.protocolDescription
    #expect(description.handshakeAttempts == 3)
    #expect(description.announceResendLimit == 8)
    #expect(GIPDriver().sessionPlan.usbStartupRetryDelays.count == 2)
  }

  @Test
  func xusbReadsTheInquiryResend() {
    #expect(XUSBDriver().inquiryResendInterval == 16)
    #expect(XUSBDriver(tuning: .init(presenceResendReports: 3)).inquiryResendInterval == 3)
  }

  @Test
  func xusbReadsTheReceiverInquiryResendLimit() throws {
    #expect(PhysicalProtocolID.xboxXUSB.protocolDescription.receiverInquiryResendLimit == 8)
    let limit = PhysicalProtocolID.xboxXUSB.described(limit: \.receiverInquiryResendLimit)
    let driver = XUSBDriver(isWirelessReceiver: true)
    // Pad reports from a slot that has not reported presence.
    let padReport = Data([0x00, 0x01, 0x00, 0x00] + [UInt8](repeating: 0, count: 20))
    var resends = 0
    for _ in 0..<(driver.inquiryResendInterval * (limit + 4)) {
      _ = try driver.parseReport(padReport)
      if !driver.drainPendingWrites().isEmpty { resends += 1 }
    }
    #expect(resends == limit)
  }

  @Test
  func xusbReadsTheTransferTimeout() {
    #expect(XUSBDriver().usbTimeoutMilliseconds == 2_000)
    #expect(
      XUSBDriver(tuning: .init(usbTransferTimeoutMilliseconds: 750)).usbTimeoutMilliseconds == 750
    )
  }

  @Test
  func sonyAdaptersReadTheDisconnectDelay() {
    #expect(DualShock4Driver().adapterDisconnectNanoseconds == 500 * Self.millisecond)
    #expect(DualSenseDriver().dongleDisconnectNanoseconds == 500 * Self.millisecond)
    let tuning = ControllerTuning(adapterDisconnectDelayMilliseconds: 40)
    #expect(DualShock4Driver(tuning: tuning).adapterDisconnectNanoseconds == 40 * Self.millisecond)
    #expect(DualSenseDriver(tuning: tuning).dongleDisconnectNanoseconds == 40 * Self.millisecond)
  }
}
