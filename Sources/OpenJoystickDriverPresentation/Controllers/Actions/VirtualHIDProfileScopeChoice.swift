import OpenJoystickDriverKit

/// Whose virtual HID profile an override changes, as `ojd virtual set` and `reset` choose it with
/// `--unit`: every controller of the model, or only the one controller by its unit ID.
enum VirtualHIDProfileScopeChoice: Hashable, CaseIterable {
  case model
  case unit

  var scope: VirtualHIDProfileOverrideScope {
    switch self {
    case .model: .model
    case .unit: .unit
    }
  }

  var titleKey: String {
    switch self {
    case .model: "controllers.virtual.scope.model"
    case .unit: "controllers.virtual.scope.unit"
    }
  }

  init(_ scope: VirtualHIDProfileOverrideScope) {
    self = scope == .unit ? .unit : .model
  }

  /// The choices for `device`. The unit scope needs a unit ID, which the service refuses to
  /// resolve for a controller that reports no location.
  static func offered(for device: ApplicationServiceDeviceDescription) -> [Self] {
    device.portKey == nil ? [.model] : [.model, .unit]
  }

  /// The scope of the stored override when one exists, else the model.
  static func initial(for device: ApplicationServiceDeviceDescription) -> Self {
    guard device.portKey != nil, let scope = device.virtualHIDProfile?.overrideScope else {
      return .model
    }
    return Self(scope)
  }
}

/// What choosing a profile in a scope does, given the override the controller reports. The
/// report names only the override in effect, which is its unit's when one exists, else its
/// model's.
enum VirtualHIDProfileOverrideDecision: Equatable {
  /// The scope already holds this choice.
  case unchanged
  /// Store the profile in the scope, or clear the scope's override for Automatic.
  case send
  /// Automatic in a scope that holds no override: the override in effect belongs to the other
  /// scope, and clearing this scope would change nothing.
  case otherScopeHolds(VirtualHIDProfileScopeChoice)

  static func decide(
    profile: VirtualHIDProfileID?,
    scope: VirtualHIDProfileScopeChoice,
    for device: ApplicationServiceDeviceDescription
  ) -> Self {
    guard let effective = device.virtualHIDProfile?.override else {
      return profile == nil ? .unchanged : .send
    }
    let holder = currentScope(for: device) ?? .model
    guard let profile else { return holder == scope ? .send : .otherScopeHolds(holder) }
    return profile == effective && holder == scope ? .unchanged : .send
  }

  /// The scope of the override in effect; nil when the controller selects automatically.
  static func currentScope(
    for device: ApplicationServiceDeviceDescription
  ) -> VirtualHIDProfileScopeChoice? {
    guard let status = device.virtualHIDProfile, status.override != nil else { return nil }
    return VirtualHIDProfileScopeChoice(status.overrideScope ?? .model)
  }
}
