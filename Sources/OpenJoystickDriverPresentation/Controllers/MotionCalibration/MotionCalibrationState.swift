#if canImport(SwiftUI)
  import Foundation
  import SwiftUI
  import OpenJoystickDriverKit

  protocol MotionCalibrationGateway: Sendable {
    func motionCalibration(
      for selector: ControllerReference,
      command: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus
  }

  @MainActor
  final class MotionCalibrationViewModel: ObservableObject {
    @Published
    private(set) var status: RemappingMotionCalibrationStatus?
    @Published
    private(set) var errorMessage: String?
    @Published
    private(set) var isBusy = false
    @Published
    private(set) var selector: ControllerReference?
    private let gateway: any MotionCalibrationGateway
    private var generation: UInt64 = 0

    init(gateway: any MotionCalibrationGateway) { self.gateway = gateway }

    func select(_ selector: ControllerReference?) {
      guard self.selector != selector else { return }
      generation &+= 1
      self.selector = selector
      status = nil
      errorMessage = nil
      isBusy = false
    }

    func refresh() async { await perform(nil) }

    func perform(_ command: RemappingMotionCalibrationCommand?) async {
      guard let selector, !isBusy else { return }
      let requestGeneration = generation
      isBusy = true
      errorMessage = nil
      do {
        let result = try await gateway.motionCalibration(for: selector, command: command)
        guard generation == requestGeneration else { return }
        status = result
      } catch {
        guard generation == requestGeneration else { return }
        status = nil
        errorMessage = Self.calibrationError(error)
      }
      isBusy = false
    }

    /// The service sends its refusals as remapping RPC errors; the gateway throws
    /// `controllerUnavailable` itself when the selector no longer resolves.
    private static func calibrationError(_ error: any Error) -> String {
      if let rejection = error as? ApplicationServiceRemappingRPCError {
        switch rejection.code {
        case .controllerUnavailable:
          return calibrationError(RemappingMotionCalibrationError.controllerUnavailable)
        case .motionUnavailable:
          return calibrationError(RemappingMotionCalibrationError.motionUnavailable)
        case .motionGyroNotSelected, .motionProfileInactive, .motionSessionChanged:
          return rejection.code.errorCode.localizedExplanation
        default: break
        }
      }
      switch error as? RemappingMotionCalibrationError {
      case .controllerUnavailable:
        return OJDLocalized.string(
          "motion.calibration.controllerUnavailable"
        )
      case .motionUnavailable:
        return OJDLocalized.string(
          "motion.calibration.motionUnavailable"
        )
      case nil: return RuntimePresentation.userFacingError(error)
      }
    }
  }
#endif
