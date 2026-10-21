#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileOutputPolicyView: View {
    let policy: RemappingOutputPolicy
    let onChange: (RemappingOutputPolicy) -> Void

    var body: some View {
      Group {
        Picker(
          OJDLocalized.string("profiles.virtualOutput"),
          selection: Binding(
            get: { policy.virtualGamepad },
            set: { value in onChange(Self.policy(selecting: value, from: policy)) }
          )
        ) {
          Text(OJDLocalized.string("profiles.virtualDisabled")).tag(
            RemappingVirtualGamepadPolicy.disabled
          )
          Text(OJDLocalized.string("profiles.virtualMapped")).tag(
            RemappingVirtualGamepadPolicy.mapped
          )
          Text(
            OJDLocalized.string(
              "profiles.virtualPassthrough"
            )
          ).tag(RemappingVirtualGamepadPolicy.passthrough)
        }
        Toggle(
          OJDLocalized.string(
            "profiles.exclusiveInput"
          ),
          isOn: Binding(
            get: { policy.requiresExclusiveInput },
            set: { value in
              onChange(
                RemappingOutputPolicy(
                  virtualGamepad: policy.virtualGamepad,
                  physicalInput: value ? .exclusive : .shared
                )
              )
            }
          )
        ).disabled(policy.virtualGamepad != .disabled)
      }
    }

    /// The policy after the virtual output changes. The exclusive toggle applies only while the
    /// virtual output is disabled, because a virtual output always takes exclusive input; any other
    /// virtual output therefore returns the physical input to `ojd profile create`'s default,
    /// shared, instead of keeping an earlier choice that the toggle no longer shows.
    static func policy(
      selecting virtualGamepad: RemappingVirtualGamepadPolicy,
      from policy: RemappingOutputPolicy
    ) -> RemappingOutputPolicy {
      RemappingOutputPolicy(
        virtualGamepad: virtualGamepad,
        physicalInput: virtualGamepad == .disabled ? policy.physicalInput : .shared
      )
    }
  }
#endif
