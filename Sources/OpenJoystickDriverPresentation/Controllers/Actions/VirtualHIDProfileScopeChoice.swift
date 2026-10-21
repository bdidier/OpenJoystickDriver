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
