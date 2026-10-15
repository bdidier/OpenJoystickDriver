#if canImport(SwiftUI)
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverTestSupport
  import Testing

  @testable import OpenJoystickDriverPresentation

  @MainActor
  struct MotionCalibrationStateTests {
    @Test
    func unavailableMotionClearsBusyStateAndProvidesRecoveryGuidance() async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail()
      await request.value
      #expect(model.status == nil)
      #expect(!model.isBusy)
      #expect(
        model.errorMessage
          == OJDLocalized.string(
            "motion.calibration.motionUnavailable"
          )
      )
    }

    @Test(arguments: [
      ApplicationServiceRemappingRPCError.Code.motionGyroNotSelected,
      .motionProfileInactive,
      .motionSessionChanged,
    ])
    func serviceRefusalShowsTheExplanationOfItsCode(
      code: ApplicationServiceRemappingRPCError.Code
    ) async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail(ApplicationServiceRemappingRPCError(code: code, message: "service text"))
      await request.value
      #expect(model.errorMessage == code.errorCode.localizedExplanation)
    }

    @Test
    func serviceMotionUnavailableGivesTheRecoveryGuidance() async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail(
        ApplicationServiceRemappingRPCError(code: .motionUnavailable, message: "service text")
      )
      await request.value
      #expect(
        model.errorMessage == OJDLocalized.string("motion.calibration.motionUnavailable")
      )
    }

    @Test
    func discardedSelectionIgnoresLateCalibrationResult() async throws {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      #expect(model.isBusy)
      model.select(nil)
      try await gateway.finish()
      await request.value
      #expect(model.status == nil)
      #expect(model.errorMessage == nil)
      #expect(!model.isBusy)
    }

    @Test
    func selectedControllerReceivesCalibrationStatus() async throws {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      let selector = ControllerReference.session(.fixture("second"))
      model.select(selector)
      let request = Task { await model.perform(.start) }
      await gateway.waitForRequest()
      await model.perform(.reset)
      #expect(await gateway.command == .start)
      #expect(await gateway.selector == selector)
      try await gateway.finish()
      await request.value
      #expect(model.status?.isCollecting == true)
      #expect(model.status?.hasMotionBaseline == true)
      #expect(!model.isBusy)
    }
  }

  private actor DelayedMotionCalibrationGateway: MotionCalibrationGateway {
    var command: RemappingMotionCalibrationCommand?
    var selector: ControllerReference?
    private var pending: CheckedContinuation<RemappingMotionCalibrationStatus, any Error>?
    private var observer: CheckedContinuation<Void, Never>?

    func motionCalibration(
      for selector: ControllerReference,
      command: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus {
      self.selector = selector
      self.command = command
      return try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        observer?.resume()
        observer = nil
      }
    }

    func waitForRequest() async {
      if pending != nil { return }
      await withCheckedContinuation { observer = $0 }
    }

    func finish() throws {
      let data = Data(
        """
        {"hasMotionBaseline":true,"isCollecting":true,
         "offsetDegreesPerSecond":{"x":0,"y":0,"z":0}}
        """.utf8
      )
      let status = try JSONDecoder().decode(RemappingMotionCalibrationStatus.self, from: data)
      pending?.resume(returning: status)
      pending = nil
    }

    func fail(_ error: any Error = RemappingMotionCalibrationError.motionUnavailable) {
      pending?.resume(throwing: error)
      pending = nil
    }
  }
#endif
