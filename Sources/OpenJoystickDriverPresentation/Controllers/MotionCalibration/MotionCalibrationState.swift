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
    /// Counts commands. A read that started before a command ended its answer is stale.
    private var commandSequence: UInt64 = 0

    init(gateway: any MotionCalibrationGateway) { self.gateway = gateway }

    func select(_ selector: ControllerReference?) {
      guard self.selector != selector else { return }
      generation &+= 1
      self.selector = selector
      status = nil
      errorMessage = nil
      isBusy = false
    }

    /// Reads the status without marking the model busy, so controls stay usable. A command
    /// that starts or ends while the read runs makes its answer stale, and it is dropped.
    func refresh() async {
      guard let selector else { return }
      let requestGeneration = generation
      let requestSequence = commandSequence
      func isCurrent() -> Bool {
        generation == requestGeneration && commandSequence == requestSequence && !isBusy
      }
      do {
        let result = try await gateway.motionCalibration(for: selector, command: nil)
        guard isCurrent() else { return }
        status = result
        errorMessage = nil
      } catch {
        guard isCurrent() else { return }
        status = nil
        errorMessage = Self.calibrationError(error)
      }
    }

    /// How long the status waits between reads while calibration is not settled.
    static let refreshIntervalNanoseconds: UInt64 = 1_000_000_000

    /// Whether the status can still change on the service side: before the motion baseline
    /// exists, and while samples are being collected. A failed read stops the loop; the user
    /// retries it.
    static func needsRefresh(
      status: RemappingMotionCalibrationStatus?,
      errorMessage: String?
    ) -> Bool {
      guard errorMessage == nil, let status else { return false }
      return !status.hasMotionBaseline || status.isCollecting
    }

    /// Reads the status, then keeps reading it every ``refreshIntervalNanoseconds`` while
    /// ``needsRefresh(status:errorMessage:)`` holds. Ends when the task is cancelled.
    func refreshWhileCalibrating(
      sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async {
      await refresh()
      while Self.needsRefresh(status: status, errorMessage: errorMessage) {
        do { try await sleep(Self.refreshIntervalNanoseconds) } catch { return }
        guard !Task.isCancelled else { return }
        await refresh()
      }
    }

    /// Sends `command` and shows the status it returns. One command runs at a time; a read in
    /// flight does not block it and its answer is dropped.
    func perform(_ command: RemappingMotionCalibrationCommand) async {
      guard let selector, !isBusy else { return }
      let requestGeneration = generation
      commandSequence &+= 1
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
      // A read that started while the command ran may predate its effect.
      commandSequence &+= 1
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
