import Foundation

extension ApplicationServiceClient {

  /// Connects to the running main app, waiting up to `timeoutSeconds` for its local server.
  ///
  /// The client never launches the app. Cancelling the calling task stops the retries and leaves
  /// the client disconnected.
  public func connect(timeoutSeconds: TimeInterval = 5) async {
    let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
    do { if try await waitForLocalServer(until: deadline) { return } } catch {}
    stateLock.withLock { connected = false }
  }

  public func disconnect() { stateLock.withLock { connected = false } }

  public var isConnected: Bool { stateLock.withLock { connected } }

  public func getStatus() async throws -> ApplicationServiceStatusPayload {
    let data: Data = try await call(.getStatus, LocalServiceRPCEmptyArguments())
    guard let payload = try? JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  public func requestRequiredAccess() async throws -> PermissionManager.Snapshot {
    try await call(.requestRequiredAccess, LocalServiceRPCEmptyArguments())
  }

  public func requestAccess(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot {
    try await call(.requestAccess, LocalServiceRPCPermissionArguments(requirement: requirement))
  }

  public func controllerState(
    for controller: ControllerReference
  ) async throws -> ControllerState? {
    let data: Data? = try await call(
      .getControllerState,
      LocalServiceRPCDeviceArguments(
        controller: controller
      )
    )
    guard let data else { return nil }
    return try? JSONDecoder().decode(ControllerState.self, from: data)
  }

  /// The values the controller's virtual gamepad last reported; nil when no virtual gamepad
  /// publishes the controller.
  public func virtualOutputState(
    for controller: ControllerReference
  ) async throws -> ApplicationServiceVirtualOutputState? {
    let data: Data? = try await call(
      .getVirtualOutputState,
      LocalServiceRPCDeviceArguments(
        controller: controller
      )
    )
    guard let data else { return nil }
    return try JSONDecoder().decode(ApplicationServiceVirtualOutputState.self, from: data)
  }

  public func packetLog(
    for controller: ControllerReference
  ) async throws -> [PacketLogEntry] {
    let data: Data = try await call(
      .getPacketLog,
      LocalServiceRPCDeviceArguments(
        controller: controller
      )
    )
    guard let entries = try? JSONDecoder().decode([PacketLogEntry].self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return entries
  }

  /// Sends one output command to the selected controller through the running app.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for controller: ControllerReference
  ) async throws -> ControllerOutputResult {
    try await call(
      .sendControllerOutput,
      LocalServiceRPCControllerOutputArguments(
        controller: controller,
        command: command
      )
    )
  }

  public func previewPhysicalColor(
    for controller: ControllerReference,
    token: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    try await call(
      .previewPhysicalColor,
      LocalServiceRPCColorPreviewArguments(
        controller: controller,
        token: token,
        red: Int(red),
        green: Int(green),
        blue: Int(blue)
      )
    )
  }

  public func releasePhysicalColorPreview(
    for controller: ControllerReference,
    token: UUID
  ) async throws -> Bool {
    try await call(
      .releasePhysicalColorPreview,
      LocalServiceRPCColorPreviewReleaseArguments(
        controller: controller,
        token: token
      )
    )
  }

  public func getVirtualDeviceDiagnostics() async throws
    -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    let data: Data = try await call(.getVirtualDeviceDiagnostics, LocalServiceRPCEmptyArguments())
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceDiagnosticsPayload.self,
        from: data
      )
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  /// Stores `profile` as the virtual HID profile override for the selected controller's model,
  /// or for that unit only when `unit` is true, and applies it to the connected controller.
  public func setVirtualHIDProfileOverride(
    _ profile: String,
    for controller: ControllerReference,
    unit: Bool = false
  ) async throws -> VirtualHIDProfileOverrideResult {
    try await call(
      .setVirtualHIDProfileOverride,
      LocalServiceRPCVirtualHIDProfileOverrideArguments(
        controller: controller,
        profile: profile,
        unit: unit
      )
    )
  }

  /// Sets who serves the controller model, macOS or OJD, in the user's record for it; the service
  /// applies it to every connected controller of the model without a replug.
  public func setControllerOwnership(
    model: ControllerModelID,
    ownership: ControllerServer
  ) async throws -> ControllerOwnershipResult {
    try await call(
      .setControllerOwnership,
      LocalServiceRPCControllerOwnershipArguments(
        vendorID: Int(model.vendorID),
        productID: Int(model.productID),
        ownership: ownership
      )
    )
  }

  /// Returns the selected controller's model, or that unit only when `unit` is true, to automatic
  /// virtual HID profile selection.
  public func resetVirtualHIDProfileOverride(
    for controller: ControllerReference,
    unit: Bool = false
  ) async throws -> VirtualHIDProfileOverrideResult {
    try await call(
      .resetVirtualHIDProfileOverride,
      LocalServiceRPCVirtualHIDProfileOverrideResetArguments(
        controller: controller,
        unit: unit
      )
    )
  }

  /// Publishes a virtual controller with the `profile` virtual HID profile, such as `hid-generic`,
  /// that this client drives with ``exchangeVirtualFeed(token:frames:)``.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  public func openVirtualFeed(profile: String) async throws -> VirtualFeedSession {
    try await call(.openVirtualFeed, LocalServiceRPCVirtualFeedOpenArguments(profile: profile))
  }

  /// Queues `frames` on the feed and returns the output commands queued since the previous
  /// exchange. Send the frames past ``VirtualFeedExchangeResult/accepted`` again later. Exchange
  /// at least every ``VirtualFeedExchangeResult/idleTimeoutSeconds`` to keep the feed open.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  public func exchangeVirtualFeed(
    token: UUID,
    frames: [VirtualFeedFrame] = []
  ) async throws -> VirtualFeedExchangeResult {
    try await call(
      .exchangeVirtualFeed,
      LocalServiceRPCVirtualFeedExchangeArguments(token: token, frames: frames)
    )
  }

  /// Removes the feed's virtual controller; false when no open feed has the token.
  ///
  /// Only OpenJoystickDriver's own signed executables can call this; other programs use
  /// `ojd virtual feed`.
  @discardableResult
  public func closeVirtualFeed(token: UUID) async throws -> Bool {
    try await call(.closeVirtualFeed, LocalServiceRPCVirtualFeedCloseArguments(token: token))
  }

  public func suspendController(
    _ controller: ControllerReference
  ) async throws -> ControllerSuspendResult {
    let data: Data = try await call(
      .suspendController,
      LocalServiceRPCDeviceArguments(
        controller: controller
      )
    )
    guard let result = try? JSONDecoder().decode(ControllerSuspendResult.self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return result
  }

  public func resumeController(
    _ controller: ControllerReference
  ) async throws -> ControllerResumeResult {
    let data: Data = try await call(
      .resumeController,
      LocalServiceRPCDeviceArguments(
        controller: controller
      )
    )
    guard let result = try? JSONDecoder().decode(ControllerResumeResult.self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return result
  }

  public func disconnectWirelessController(
    _ controller: ControllerReference
  ) async throws -> WirelessControllerDisconnectResult {
    let data: Data = try await call(
      .disconnectWirelessController,
      LocalServiceRPCDeviceArguments(
        controller: controller
      ),
      timeoutSeconds: 5
    )
    guard
      let result = try? JSONDecoder().decode(WirelessControllerDisconnectResult.self, from: data)
    else { throw ApplicationServiceClientError.invalidResponse }
    return result
  }

  public func resetSettings() async throws -> Bool {
    try await call(.resetSettings, LocalServiceRPCEmptyArguments())
  }

  /// Reads every app setting.
  public func getSettings() async throws -> ApplicationSettingsPayload {
    try await call(.getSettings, LocalServiceRPCEmptyArguments())
  }

  /// Applies one app setting and returns every setting as it stands afterward, because macOS can
  /// leave a setting off, such as a login item that needs approval.
  public func setSetting(
    _ key: ApplicationSettingKey,
    to value: Bool
  ) async throws -> ApplicationSettingsPayload {
    try await call(.setSetting, ApplicationServiceSettingArguments(key: key, value: value))
  }

  /// The endpoint's state, its grants, and the clients it refused recently.
  public func accessStatus() async throws -> AccessStatusPayload {
    try await call(.getAccessStatus, LocalServiceRPCEmptyArguments())
  }

  /// Turns the endpoint on or off and returns its state afterward.
  public func setAccessEnabled(_ enabled: Bool) async throws -> AccessStatusPayload {
    try await call(.setAccessEnabled, AccessEnabledArguments(enabled: enabled))
  }

  /// Grants `scopes` to the client signed as `identity`, adding to any scopes it already has.
  public func grantAccess(
    _ identity: CodeSigningIdentity,
    path: String,
    scopes: [EndpointScope]
  ) async throws -> AccessGrantSummary {
    try await call(
      .grantAccess,
      AccessGrantArguments(identity: identity, path: path, scopes: scopes)
    )
  }

  /// Removes `scopes` from the client's grant, or the whole grant when nil.
  public func revokeAccess(id: String, scopes: [EndpointScope]?) async throws -> AccessRevokeResult
  {
    try await call(.revokeAccess, AccessRevokeArguments(id: id, scopes: scopes))
  }

  /// Grants `scopes` to a new token that pages from `origins` may use on the WebSocket; the
  /// result holds the token, which the service does not keep.
  public func grantTokenAccess(
    name: String,
    origins: [String],
    scopes: [EndpointScope]
  ) async throws -> AccessTokenGrantResult {
    try await call(
      .grantTokenAccess,
      AccessTokenGrantArguments(name: name, origins: origins, scopes: scopes)
    )
  }

  /// Turns the WebSocket on or off and returns the endpoint's state afterward; a nil `port` keeps
  /// the saved port.
  public func setWebAccess(enabled: Bool, port: Int?) async throws -> AccessStatusPayload {
    try await call(.setWebAccess, AccessWebArguments(enabled: enabled, port: port))
  }

  public func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(.getRemappingSnapshot, LocalServiceRPCEmptyArguments())
  }

  public func remappingMotionCalibration(
    for controller: ControllerReference,
    command: RemappingMotionCalibrationCommand? = nil
  ) async throws -> RemappingMotionCalibrationStatus {
    try await call(
      .remappingMotionCalibration,
      ApplicationServiceMotionCalibrationArguments(
        controller: controller,
        command: command
      )
    )
  }
}
