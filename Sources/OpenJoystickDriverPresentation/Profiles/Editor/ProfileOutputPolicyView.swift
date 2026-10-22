#if canImport(AppKit) && canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileOutputPolicyView: View {
    let policy: RemappingOutputPolicy
    let onChange: (RemappingOutputPolicy) -> Void

    var body: some View {
      Group {
        Picker(
          OJDLocalized.string("ui.profiles.virtualOutput"),
          selection: Binding(
            get: { policy.virtualGamepad },
            set: { value in onChange(Self.policy(selecting: value, from: policy)) }
          )
        ) {
          Text(OJDLocalized.string("ui.profiles.virtualDisabled")).tag(
            RemappingVirtualGamepadPolicy.disabled
          )
          Text(OJDLocalized.string("ui.profiles.virtualMapped")).tag(
            RemappingVirtualGamepadPolicy.mapped
          )
          Text(
            OJDLocalized.string(
              "ui.profiles.virtualPassthrough"
            )
          ).tag(RemappingVirtualGamepadPolicy.passthrough)
        }
        Toggle(
          OJDLocalized.string(
            "ui.profiles.exclusiveInput"
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
    /// virtual output is disabled; with any other virtual output it is disabled and shows
    /// exclusive input as on, because a virtual output always takes exclusive input. Any other
    /// virtual output therefore returns the physical input to `ojd profile create`'s default,
    /// shared, so an earlier choice that the toggle does not show is not kept.
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
