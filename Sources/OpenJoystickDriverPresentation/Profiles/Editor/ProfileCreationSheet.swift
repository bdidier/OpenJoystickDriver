#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The editable fields of the New Profile sheet. The profile belongs to one connected
  /// controller, chosen by its session token; its name starts as the controller's name and follows
  /// the choice until the person edits it.
  struct ProfileCreationFields: Equatable {
    var name: String
    var deviceToken: String?
    var scopeKind: ProfileScopeKind
    var appID: String

    /// The fields as the sheet opens: the first controller is chosen and names the profile.
    static func initial(devices: [ApplicationServiceDeviceDescription]) -> Self {
      Self(
        name: defaultName(for: devices.first),
        deviceToken: devices.first?.sessionToken.rawValue,
        scopeKind: .global,
        appID: ""
      )
    }

    /// The name a profile for `device` starts with: the controller's own name, empty when it has
    /// none.
    static func defaultName(for device: ApplicationServiceDeviceDescription?) -> String {
      device?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The chosen controller among `devices`.
    func device(
      in devices: [ApplicationServiceDeviceDescription]
    )
      -> ApplicationServiceDeviceDescription?
    {
      devices.first { $0.sessionToken.rawValue == deviceToken }
    }

    /// Chooses `token`; a name still equal to the previous controller's default follows the new
    /// controller, an edited name stays.
    mutating func selectDevice(_ token: String, in devices: [ApplicationServiceDeviceDescription]) {
      let previousDefault = Self.defaultName(for: device(in: devices))
      deviceToken = token
      if name == previousDefault { name = Self.defaultName(for: device(in: devices)) }
    }

    /// The profile these fields describe, or nil while a field is missing or invalid.
    func proposedProfile(devices: [ApplicationServiceDeviceDescription]) -> RemappingProfile? {
      guard let device = device(in: devices) else { return nil }
      let applicationScope: RemappingApplicationScope
      switch scopeKind {
      case .global: applicationScope = .global
      case .application: applicationScope = .application(appID: appID)
      }
      let profile = RemappingProfile(
        name: ProfileNameValidation.trimmedName(name),
        device: RemappingDeviceScope(vendorID: device.vendorID, productID: device.productID),
        applicationScope: applicationScope,
        bindings: []
      )
      guard (try? profile.validate()) != nil else { return nil }
      return profile
    }

    /// Validation is shown only once a field differs from the opening state and the fields do not
    /// make a valid profile.
    func showsValidation(comparedTo initial: Self, isValid: Bool) -> Bool {
      !isValid && self != initial
    }
  }

  struct ProfileNameSheet: View {
    let title: String
    let devices: [ApplicationServiceDeviceDescription]
    let onCreate: (String, RemappingDeviceScope, RemappingApplicationScope) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var fields: ProfileCreationFields
    private let initialFields: ProfileCreationFields

    init(
      title: String,
      devices: [ApplicationServiceDeviceDescription],
      onCreate: @escaping (String, RemappingDeviceScope, RemappingApplicationScope) -> Void
    ) {
      self.title = title
      self.devices = devices
      self.onCreate = onCreate
      let initialFields = ProfileCreationFields.initial(devices: devices)
      self.initialFields = initialFields
      _fields = State(initialValue: initialFields)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.headline)
        Form {
          if devices.isEmpty {
            Text(OJDLocalized.string("status.connectController"))
              .foregroundColor(Color(NSColor.secondaryLabelColor))
          } else {
            TextField(OJDLocalized.string("common.profileName"), text: $fields.name)
            if !fields.name.isEmpty && trimmedName.isEmpty {
              Text(OJDLocalized.string("capture.profileNameValidation"))
                .foregroundColor(Color(NSColor.systemRed)).fixedSize(
                  horizontal: false,
                  vertical: true
                )
            }
            Picker(OJDLocalized.string("common.controller"), selection: deviceBinding) {
              ForEach(devices, id: \.sessionToken) { device in
                Text(device.name).tag(device.sessionToken.rawValue)
              }
            }
            Picker(OJDLocalized.string("profiles.target"), selection: $fields.scopeKind) {
              Text(OJDLocalized.string("profiles.targetGlobal")).tag(ProfileScopeKind.global)
              Text(OJDLocalized.string("profiles.targetApplication")).tag(
                ProfileScopeKind.application
              )
            }
            if fields.scopeKind == .application {
              TextField(OJDLocalized.string("profiles.appID"), text: $fields.appID)
            }
            if fields.showsValidation(comparedTo: initialFields, isValid: canCreate) {
              Text(OJDLocalized.string("profiles.creationValidation"))
                .foregroundColor(Color(NSColor.systemRed)).fixedSize(
                  horizontal: false,
                  vertical: true
                )
            }
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.create")) {
            guard let proposedProfile else { return }
            onCreate(proposedProfile.name, proposedProfile.device, proposedProfile.applicationScope)
            presentationMode.wrappedValue.dismiss()
          }.disabled(!canCreate)
        }
      }.padding(20).frame(width: 420)
    }

    private var trimmedName: String { ProfileNameValidation.trimmedName(fields.name) }

    private var canCreate: Bool { proposedProfile != nil }

    private var proposedProfile: RemappingProfile? { fields.proposedProfile(devices: devices) }

    private var deviceBinding: Binding<String> {
      Binding(
        get: { fields.deviceToken ?? "" },
        set: { fields.selectDevice($0, in: devices) }
      )
    }
  }

#endif
