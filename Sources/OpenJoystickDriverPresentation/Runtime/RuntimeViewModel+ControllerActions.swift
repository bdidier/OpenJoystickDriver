import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  func listenForInput(for selector: ControllerReference) async {
    inputGeneration += 1
    let generation = inputGeneration
    inputCaptureState = .listening(selector)
    var baselineState: ControllerState?

    for attempt in 0..<50 {
      guard generation == inputGeneration else { return }
      do {
        if let state = try await gateway.controllerState(for: selector) {
          guard generation == inputGeneration else { return }
          if let baselineState,
            let detectedSource = RuntimePresentation.detectedTransition(
              from: baselineState,
              to: state
            )
          {
            inputCaptureState = .detected(selector, state, detectedSource)
            return
          }
          baselineState = state
        }
        if attempt < 49 { try await Task.sleep(nanoseconds: 100_000_000) }
      } catch is CancellationError {
        guard generation == inputGeneration else { return }
        inputCaptureState = .idle
        return
      } catch {
        guard generation == inputGeneration else { return }
        let message = RuntimePresentation.userFacingError(error)
        inputCaptureState =
          RuntimePresentation.isUnavailable(error)
          ? .unavailable(selector, message) : .error(selector, message)
        return
      }
    }

    guard generation == inputGeneration else { return }
    inputCaptureState = .unavailable(
      selector,
      OJDLocalized.string(
        "ui.error.noDetectedControl"
      )
    )
  }

  func cancelInputCapture() {
    inputGeneration += 1
    inputCaptureState = .idle
  }

  func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "ui.error.actionInProgress"
      )
    }
    do {
      remappingState = .available(
        try await gateway.pairRemappingJoyCons(left: left, right: right, profileID: profileID)
      )
      return nil
    } catch { return RuntimePresentation.userFacingError(error) }
  }

  func unpairRemappingJoyCons(sessionID: UUID) async -> String? {
    guard !mutationInFlight else {
      return OJDLocalized.string(
        "ui.error.actionInProgress"
      )
    }
    do {
      remappingState = .available(try await gateway.unpairRemappingJoyCons(sessionID: sessionID))
      return nil
    } catch { return RuntimePresentation.userFacingError(error) }
  }

  /// Stores `profile` as the virtual HID profile override of `device`'s model, or of `device`
  /// alone for the `.unit` scope, or clears that override when `profile` is nil so the controller
  /// selects automatically.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID?,
    for device: ApplicationServiceDeviceDescription,
    scope: VirtualHIDProfileOverrideScope = .model
  ) async {
    // The service retargets every controller of the model, so the request and its failure
    // belong to the model rather than to one controller.
    let model = RuntimeControllerModel(device)
    guard virtualHIDProfileOverrideStates[model]?.inFlight != true else { return }
    virtualHIDProfileOverrideStates[model] = RuntimeVirtualHIDProfileOverrideState(
      request: profile.map { .set($0) } ?? .reset
    )
    let selector = ControllerReference.session(device.sessionToken)
    var failure: String?
    do {
      let result: VirtualHIDProfileOverrideResult
      if let profile {
        result = try await gateway.setVirtualHIDProfileOverride(
          profile,
          for: selector,
          scope: scope
        )
      } else {
        result = try await gateway.resetVirtualHIDProfileOverride(for: selector, scope: scope)
      }
      failure = result.failure.map(RuntimePresentation.virtualHIDProfileOverrideFailure)
    } catch { failure = RuntimePresentation.userFacingError(error) }
    // Keep the request in flight until the refreshed status carries the model's new profile.
    await refreshControllerInventory()
    virtualHIDProfileOverrideStates[model] = failure.map {
      RuntimeVirtualHIDProfileOverrideState(failure: $0)
    }
  }

  /// Returns every controller model, also those not connected, to automatic virtual HID profile
  /// selection and refreshes the inventory. Returns why the service could not apply it, or nil.
  func resetAllVirtualHIDProfileOverrides() async -> String? {
    var failure: String?
    do {
      if try await !gateway.resetAllVirtualHIDProfileOverrides() {
        failure = OJDLocalized.string("ui.controllers.virtual.resetAllFailed")
      }
    } catch { failure = RuntimePresentation.userFacingError(error) }
    await refreshControllerInventory()
    return failure
  }

  /// Sets who serves `device`'s model, `server`: macOS natively, or OpenJoystickDriver as a virtual
  /// controller. A refusal shows in the controller's detail, with the service's detail text for a
  /// record that is invalid or cannot be written.
  func setControllerServer(
    _ server: ControllerServer,
    for device: ApplicationServiceDeviceDescription
  ) async {
    var accepted = false
    await performControllerAction(device) {
      let result = try await gateway.setControllerServer(
        model: ControllerModelID(vendorID: device.vendorID, productID: device.productID),
        server: server
      )
      guard let failure = result.failure else {
        accepted = true
        return nil
      }
      return RuntimePresentation.controllerServerFailure(failure, detail: result.detail)
    }
    guard accepted else { return }
    await waitForRecordServer(server, of: RuntimeControllerModel(device))
  }

  /// Refreshes the inventory every 200 ms, for at most 2 seconds, until a controller of `model`
  /// reports `server`. The service reloads the records after it answers, so the first refresh
  /// can still carry the old value.
  private func waitForRecordServer(
    _ server: ControllerServer,
    of model: RuntimeControllerModel
  ) async {
    for _ in 0..<10 {
      if case .available(let status) = statusState,
        status.devices.contains(where: {
          RuntimeControllerModel($0) == model && $0.recordServer == server
        })
      {
        return
      }
      do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
      await refreshControllerInventory()
    }
  }

  func suspendController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.suspendController(
        ControllerReference.session(device.sessionToken)
      )
      guard result.succeeded || result.failure == .alreadySuspended else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      return nil
    }
  }

  func resumeController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.resumeController(
        ControllerReference.session(device.sessionToken)
      )
      guard result.succeeded || result.failure == .alreadyActive else {
        throw ApplicationServiceGatewayError.controllerSessionChangeRejected
      }
      return nil
    }
  }

  func disconnectWirelessController(_ device: ApplicationServiceDeviceDescription) async {
    await performControllerAction(device) {
      let result = try await gateway.disconnectWirelessController(
        ControllerReference.session(device.sessionToken)
      )
      guard let failure = result.failure else { return nil }
      let code = result.systemCode.map(String.init) ?? "none"
      print(
        "[RuntimeViewModel] Wireless disconnect failed: \(failure.rawValue), "
          + "stage \(result.failedStage?.rawValue ?? "none"), code \(code), "
          + "detail \(result.detail ?? "none"), recovery \(result.recovery ?? "none")"
      )
      return ControllerDetailLabels.wirelessDisconnectFailureText(failure)
    }
  }

  /// Runs `action` for `device`, refreshes the inventory, then records the failure `action`
  /// returned or threw so the controller's detail view shows it.
  private func performControllerAction(
    _ device: ApplicationServiceDeviceDescription,
    _ action: () async throws -> String?
  ) async {
    controllerActionFailures[device.sessionToken.rawValue] = nil
    var failure: String?
    do { failure = try await action() } catch {
      failure = RuntimePresentation.userFacingError(error)
    }
    await refreshControllerInventory()
    controllerActionFailures[device.sessionToken.rawValue] = failure
  }
}
