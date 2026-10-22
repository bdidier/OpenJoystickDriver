#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileMetadataSheet: View {
    let profile: RemappingProfile
    let onSave: (RemappingProfile) -> Void
    @Environment(\.presentationMode)
    var presentationMode
    @State
    private var name: String
    @State
    private var vendorID: String
    @State
    private var productID: String
    @State
    private var scopeKind: ProfileScopeKind
    @State
    private var appID: String
    @State
    private var joyConPairEnabled: Bool
    @State
    private var joyConGyroSelection: RemappingJoyConGyroSelection
    @State
    private var errorMessage: String?

    init(profile: RemappingProfile, onSave: @escaping (RemappingProfile) -> Void) {
      self.profile = profile
      self.onSave = onSave
      _name = State(initialValue: profile.name)
      _vendorID = State(initialValue: ProfileIdentifierInput.formatted(profile.device.vendorID))
      _productID = State(initialValue: ProfileIdentifierInput.formatted(profile.device.productID))
      _scopeKind = State(initialValue: ProfileScopeKind(profile.applicationScope))
      let appID: String
      if case .application(let value) = profile.applicationScope {
        appID = value
      } else {
        appID = ""
      }
      _appID = State(initialValue: appID)
      _joyConPairEnabled = State(initialValue: profile.joyConPair != nil)
      _joyConGyroSelection = State(initialValue: profile.joyConPair?.gyroSelection ?? .right)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text(OJDLocalized.string("ui.profiles.details")).font(
          .headline.weight(.semibold)
        )
        TextField(OJDLocalized.string("term.profileName"), text: $name)
        HStack(spacing: 12) {
          TextField(
            OJDLocalized.string("ui.profiles.vendorID"),
            text: $vendorID
          )
          TextField(
            OJDLocalized.string("ui.profiles.productID"),
            text: $productID
          )
        }
        Text(
          OJDLocalized.string(
            "ui.profiles.identifierHint"
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker(OJDLocalized.string("ui.profiles.target"), selection: $scopeKind) {
          Text(OJDLocalized.string("ui.profiles.targetGlobal")).tag(
            ProfileScopeKind.global
          )
          Text(OJDLocalized.string("ui.profiles.targetApplication")).tag(
            ProfileScopeKind.application
          )
        }
        if scopeKind == .application {
          TextField(
            OJDLocalized.string("ui.profiles.appID"),
            text: $appID
          )
        }
        Toggle(
          OJDLocalized.string("ui.profiles.joyConPair"),
          isOn: $joyConPairEnabled
        )
        if joyConPairEnabled {
          Picker(
            OJDLocalized.string("ui.profiles.joyConGyro"),
            selection: $joyConGyroSelection
          ) {
            Text(OJDLocalized.string("status.disabled")).tag(
              RemappingJoyConGyroSelection.disabled
            )
            Text(OJDLocalized.string("ui.profiles.joyConLeft")).tag(
              RemappingJoyConGyroSelection.left
            )
            Text(OJDLocalized.string("ui.profiles.joyConRight")).tag(
              RemappingJoyConGyroSelection.right
            )
          }
        }
        if let errorMessage {
          Text(errorMessage).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }
          Button(OJDLocalized.string("action.apply")) { save() }
        }
      }.padding(28).frame(width: 440)
    }

    private func save() {
      guard let vendorID = ProfileIdentifierInput.parse(vendorID),
        let productID = ProfileIdentifierInput.parse(productID)
      else {
        errorMessage = OJDLocalized.string(
          "ui.profiles.invalidIdentifiers"
        )
        return
      }
      let scope: RemappingApplicationScope
      switch scopeKind {
      case .global: scope = .global
      case .application: scope = .application(appID: appID)
      }
      let candidate = RemappingProfile(
        id: profile.id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
        applicationScope: scope,
        outputPolicy: profile.outputPolicy,
        motionTuning: profile.motionTuning,
        gyroOutput: profile.gyroOutput,
        joyConPair: joyConPairEnabled
          ? RemappingJoyConPairSettings(gyroSelection: joyConGyroSelection) : nil,
        stickMappings: profile.stickMappings,
        triggerMappings: profile.triggerMappings,
        touchMappings: profile.touchMappings,
        bindings: profile.bindings,
        chords: profile.chords,
        sequences: profile.sequences,
        layers: profile.layers
      )
      do {
        try candidate.validate()
        onSave(candidate)
        dismiss()
      } catch { errorMessage = RuntimePresentation.userFacingError(error) }
    }

    func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

  struct BindingBehaviorSheet: View {
    let binding: RemappingBinding
    let onSave: SaveAction
    let showsAdditionalActions: Bool
    let capabilities: ControllerProfileCapabilities?
    @Environment(\.presentationMode)
    var presentationMode
    @State
    var additionalActions: [RemappingAction]
    @State
    var behavior: RemappingBindingBehavior
    @State
    var pulseDurationMs: Double
    @State
    var turboEnabled: Bool
    @State
    var turboRate: Double
    @State
    var turboDuty: Double
    @State
    var longHoldEnabled: Bool
    @State
    var longHoldDuration: Double
    @State
    var longHoldDestination: RemappingDestination
    @State
    var doubleTapEnabled: Bool
    @State
    var doubleTapWindow: Double
    @State
    var doubleTapDestination: RemappingDestination

    init(
      binding: RemappingBinding,
      showsAdditionalActions: Bool = true,
      capabilities: ControllerProfileCapabilities? = nil,
      onSave: @escaping SaveAction
    ) {
      self.binding = binding
      self.onSave = onSave
      self.showsAdditionalActions = showsAdditionalActions
      self.capabilities = capabilities
      _additionalActions = State(initialValue: binding.additionalActions)
      _behavior = State(initialValue: binding.behavior)
      _pulseDurationMs = State(initialValue: binding.pulseDurationMs)
      _turboEnabled = State(initialValue: binding.turbo != nil)
      _turboRate = State(initialValue: binding.turbo?.repeatRateHz ?? 12)
      _turboDuty = State(initialValue: binding.turbo?.dutyCycle ?? 0.5)
      _longHoldEnabled = State(initialValue: binding.longHold != nil)
      _longHoldDuration = State(initialValue: binding.longHold?.durationMs ?? 500)
      _longHoldDestination = State(
        initialValue: binding.longHold?.destination ?? .keyboard(key: .space, modifiers: [])
      )
      _doubleTapEnabled = State(initialValue: binding.doubleTap != nil)
      _doubleTapWindow = State(initialValue: binding.doubleTap?.windowMs ?? 300)
      _doubleTapDestination = State(
        initialValue: binding.doubleTap?.destination ?? .keyboard(key: .space, modifiers: [])
      )
    }
  }

#endif
