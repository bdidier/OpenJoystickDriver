import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  func pairJoyCons(
    left: LogicalControllerID,
    right: LogicalControllerID,
    profile: RemappingProfile,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws -> UUID {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    let permit = try requireOperationalPermit(proposedPermit)
    guard connectedIdentifiers.contains(left), connectedIdentifiers.contains(right)
    else { throw RemappingJoyConPairError.controllerUnavailable }
    let leftIdentity = left.hardware
    let rightIdentity = right.hardware
    guard
      JoyConHalf(vendorID: leftIdentity.model.vendorID, productID: leftIdentity.model.productID)
        == .left,
      JoyConHalf(vendorID: rightIdentity.model.vendorID, productID: rightIdentity.model.productID)
        == .right,
      left != right
    else { throw RemappingJoyConPairError.invalidControllerSide }
    guard joyConPairByMember[left] == nil, joyConPairByMember[right] == nil else {
      throw RemappingJoyConPairError.memberAlreadyPaired
    }
    guard profile.joyConPair != nil else { throw RemappingJoyConPairError.profileNotPairable }
    try profile.validate()

    try await retireCurrentRoute(for: left, requiring: permit)
    try await retireCurrentRoute(for: right, requiring: permit)
    let session = RemappingJoyConPairSession(id: UUID(), left: left, right: right, profile: profile)
    joyConPairs[session.id] = session
    joyConPairByMember[left] = session.id
    joyConPairByMember[right] = session.id
    let environment = sampleEligibilityEnvironment()
    let pendingRoute = RemappingControllerRoute(
      selection: .remapping(profile),
      eligibilitySnapshot: RemappingEligibilitySnapshot(
        eligibility: .unavailable,
        environment: environment
      ),
      error: nil
    )
    routes[left] = pendingRoute
    routes[right] = pendingRoute
    do { try await reconcileJoyConPair(session, environment: environment, requiring: permit) } catch
    {
      joyConPairs.removeValue(forKey: session.id)
      joyConPairByMember.removeValue(forKey: left)
      joyConPairByMember.removeValue(forKey: right)
      routes.removeValue(forKey: left)
      routes.removeValue(forKey: right)
      throw error
    }
    return session.id
  }

  func unpairJoyCons(
    _ sessionID: UUID,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    let permit = try requireOperationalPermit(proposedPermit)
    guard let session = joyConPairs[sessionID] else {
      throw RemappingJoyConPairError.sessionUnavailable
    }
    try await cancelJoyConPair(session, requiring: permit)
    for member in session.members where connectedIdentifiers.contains(member) {
      try await loadSelection(for: member, requiring: permit)
    }
  }

  func cancelAllJoyConPairs(requiring permit: RemappingEmissionPermit) async throws {
    for session in joyConPairs.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      try await cancelJoyConPair(session, requiring: permit)
    }
  }

  func stopPairedJoyCon(
    _ identifier: LogicalControllerID,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws -> Bool {
    guard let sessionID = joyConPairByMember[identifier], let session = joyConPairs[sessionID]
    else { return false }
    let permit = try requireOperationalPermit(proposedPermit)
    try await cancelJoyConPair(session, requiring: permit)
    connectedIdentifiers.remove(identifier)
    inputOwnership.removeValue(forKey: identifier)
    for member in session.members
    where member != identifier && connectedIdentifiers.contains(member) {
      try await loadSelection(for: member, requiring: permit)
    }
    return true
  }

  func pairSession(for identifier: LogicalControllerID) -> RemappingJoyConPairSession? {
    joyConPairByMember[identifier].flatMap { joyConPairs[$0] }
  }

  /// A paired half's snapshot with its motion kept only when the pair takes gyro from it.
  func pairEvent(_ event: ControllerEvent, from identifier: LogicalControllerID) -> ControllerEvent
  {
    guard let session = pairSession(for: identifier), let settings = session.profile.joyConPair
    else { return event }
    let keepsMotion =
      switch settings.gyroSelection {
      case .disabled: false
      case .left: identifier == session.left
      case .right: identifier == session.right
      }
    guard !keepsMotion else { return event }
    return ControllerEvent(
      timestamp: event.timestamp,
      state: event.state,
      touchFrames: event.touchFrames,
      isFresh: event.isFresh
    )
  }

  func sortedJoyConPairs() -> [RemappingJoyConPairSession] {
    joyConPairs.values.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  func reconcileJoyConPair(
    _ session: RemappingJoyConPairSession,
    environment: RemappingEligibilityEnvironment,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    let eligibility = joyConPairEligibility(session, environment: environment)
    if eligibility != .eligible, routes[session.left]?.eligibility == .eligible {
      await endSources(session.members)
    }
    let permit = try requireOperationalPermit(proposedPermit)
    do {
      if eligibility == .eligible {
        try await engine.setProfile(session.profile, for: session.left, requiring: permit)
      } else {
        try await engine.releaseAll(for: session.left, requiring: permit)
      }
    } catch let error as RemappingEventEngineError {
      recordEngineFailure(error)
      throw RemappingOutputRoutingError.engine(error)
    }
    for member in session.members {
      guard var route = routes[member] else { continue }
      route.eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: eligibility,
        environment: environment
      )
      route.error = nil
      routes[member] = route
    }
  }

  private func joyConPairEligibility(
    _ session: RemappingJoyConPairSession,
    environment: RemappingEligibilityEnvironment
  ) -> RemappingRouteEligibility {
    let profile = session.profile
    let eligibility = RemappingForegroundPolicy.eligibility(
      for: profile.applicationScope,
      frontmostAppID: environment.frontmostAppID,
      accessState: environment.postEventAccessState,
      outputSuppressed: controls.outputSuppressed,
      requiresPostEventAccess: profile.requiresSystemInputAccess
    )
    guard eligibility == .eligible else { return eligibility }
    if profile.outputPolicy.requiresExclusiveInput,
      session.members.contains(where: { inputOwnership[$0] != .exclusive })
    {
      return .physicalInputNotExclusive
    }
    return .eligible
  }

  private func retireCurrentRoute(
    for identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    guard let route = routes.removeValue(forKey: identifier) else { return }
    await engine.endSource(identifier)
    switch route.selection {
    case .virtualGamepad: await notifyVirtualGamepadStop(identifier)
    case .remapping(let profile):
      try await releaseAndRetire(for: identifier, profile: profile, requiring: permit)
    case .unavailable: try await releaseAllSafely(for: identifier, requiring: permit)
    }
  }

  private func cancelJoyConPair(
    _ session: RemappingJoyConPairSession,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    var releaseError: (any Error)?
    do { try await releaseAllSafely(for: session.left, requiring: permit) } catch {
      releaseError = error
    }
    if session.profile.outputPolicy.virtualGamepad != .disabled {
      await notifyVirtualGamepadStop(session.left)
    }
    joyConPairs.removeValue(forKey: session.id)
    await endSources(session.members)
    for member in session.members {
      joyConPairByMember.removeValue(forKey: member)
      routes.removeValue(forKey: member)
    }
    if let releaseError { throw releaseError }
  }
}
