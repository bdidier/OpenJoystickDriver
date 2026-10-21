import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowProblemTests {
  private func status(inputRead: PermissionManager.AccessState) -> RuntimeStatusState {
    .available(
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: inputRead,
          inputInject: .granted,
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready")
        )
      )
    )
  }

  private func permissions(_ read: RuntimePermissionState) -> RuntimePermissionLoadState {
    .available(RuntimePermissionSummary(inputRead: read, inputInject: .granted))
  }

  @Test
  func aHealthyAppHasNoProblemAndNoBanner() {
    #expect(
      MainWindowProblem.current(
        permissions: permissions(.granted),
        status: status(inputRead: .granted),
        driver: .active
      ).isEmpty
    )
    #expect(
      MainWindowProblem.current(permissions: .loading, status: .loading, driver: .checking)
        .isEmpty
    )
  }

  @Test
  func theAccessProblemFollowsTheSameRuleAsTheStatusItemAndTheAccessArea() {
    let cases: [(RuntimePermissionLoadState, RuntimeStatusState, Bool)] = [
      (permissions(.granted), status(inputRead: .denied), false),
      (permissions(.denied), status(inputRead: .granted), true),
      (permissions(.unknown), .loading, true),
      (.requesting, status(inputRead: .unknown), false),
      (.loading, status(inputRead: .unknown), false),
      (.error("failed"), status(inputRead: .unknown), true),
      (.unavailable, status(inputRead: .denied), true),
      (.unavailable, .unavailable("down"), false),
    ]
    for (reading, payload, isMissing) in cases {
      let problems = MainWindowProblem.current(
        permissions: reading,
        status: payload,
        driver: .active
      )
      #expect(problems.contains(.accessMissing) == isMissing, "\(reading)")
    }
    #expect(
      !MainWindowProblem.current(
        permissions: permissions(.granted),
        status: status(inputRead: .denied),
        driver: .active
      ).contains(.accessMissing)
    )
  }

  @Test
  func problemsRunFromServiceToDriverToAccess() {
    #expect(
      MainWindowProblem.current(
        permissions: .unavailable,
        status: .unavailable("down"),
        driver: .awaitingApproval
      )
        == [.serviceUnavailable("down"), .driver(.awaitingApproval)]
    )
    #expect(
      MainWindowProblem.current(
        permissions: permissions(.denied),
        status: status(inputRead: .denied),
        driver: .failed
      )
        == [.driver(.failed), .accessMissing]
    )
  }

  @Test
  func eachProblemNamesItsAction() {
    #expect(MainWindowProblem.serviceUnavailable("down").action == .retryService)
    #expect(MainWindowProblem.driver(.awaitingApproval).action == .openDriverApproval)
    #expect(MainWindowProblem.driver(.needsActivation).action == .repairDriver)
    #expect(MainWindowProblem.driver(.invalid).action == .repairDriver)
    #expect(MainWindowProblem.driver(.missingEmbedded).action == nil)
    #expect(MainWindowProblem.accessMissing.action == .showAccess)
  }

  @Test
  func onlyProblemsThatNeedTheServiceOrAReinstallAreFailures() {
    #expect(MainWindowProblem.serviceUnavailable("down").isFailure)
    #expect(MainWindowProblem.driver(.missingEmbedded).isFailure)
    #expect(!MainWindowProblem.driver(.awaitingApproval).isFailure)
    #expect(!MainWindowProblem.accessMissing.isFailure)
  }

  @Test
  func anEmptyOrMissingValueShowsAHyphen() {
    #expect(OJDValue(nil).displayText == OJDLocalized.string("common.none"))
    #expect(OJDValue("").displayText == OJDLocalized.string("common.none"))
    #expect(OJDValue(nil).accessibilityKey == "common.none")
    #expect(OJDValue("Xbox One").displayText == "Xbox One")
    #expect(OJDValue("Xbox One").accessibilityKey == nil)
  }

  @Test
  func reportedValuesWithoutContentShowAHyphen() {
    #expect(OJDValue.reported("  \n") == .none)
    #expect(OJDValue.reported(nil) == .none)
    #expect(OJDValue.reported(" USB ") == .text("USB"))
    #expect(OJDValue.endpoint(0) == .none)
    #expect(OJDValue.endpoint(0x82) == .text("0x82"))
    #expect(OJDValue.usbIdentifier(vendorID: 0, productID: 0) == .none)
    #expect(OJDValue.usbIdentifier(vendorID: 0x3537, productID: 0x1010) == .text("3537:1010"))
    #expect(OJDValue.usbIdentifier(vendorID: 0, productID: 5) == .text("0000:0005"))
  }

  @Test
  func sentencesReadAMissingValueAsAWordAndNotAHyphen() {
    #expect(OJDValue.none.spokenText == OJDLocalized.string("common.none"))
    #expect(OJDValue.none.spokenText != "-")
    #expect(OJDValue.text("x").spokenText == "x")
  }

  @Test
  func theSerialNumberStartsHiddenAndTheEyeTogglesIt() {
    var visibility = SerialNumberVisibility()
    let serial = OJDValue.text("ABC123")
    #expect(visibility.presentation(of: serial).isObscured)
    #expect(visibility.presentation(of: serial).displayText != "ABC123")
    #expect(
      visibility.presentation(of: serial).spokenText
        == OJDLocalized.string("controllers.serial.hidden")
    )
    #expect(visibility.presentation(of: serial).toggleSymbolName == "eye")
    visibility.toggle()
    #expect(visibility.presentation(of: serial).displayText == "ABC123")
    #expect(visibility.presentation(of: serial).spokenText == "ABC123")
    #expect(visibility.presentation(of: serial).toggleSymbolName == "eye.slash")
    visibility.toggle()
    #expect(visibility.presentation(of: serial).isObscured)
  }

  @Test
  func aMissingSerialNumberShowsTheHyphenWithoutAnEye() {
    let presentation = SerialNumberVisibility().presentation(of: .none)
    #expect(!presentation.canToggle)
    #expect(!presentation.isObscured)
    #expect(presentation.displayText == OJDLocalized.string("common.none"))
  }
}
