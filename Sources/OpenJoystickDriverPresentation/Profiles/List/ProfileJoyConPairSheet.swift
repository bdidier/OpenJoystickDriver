#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileJoyConPairSheet: View {
    let profile: RemappingProfile
    let devices: [ApplicationServiceDeviceDescription]
    let onPair: (ControllerSessionToken, ControllerSessionToken) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var leftSessionToken: ControllerSessionToken?
    @State
    private var rightSessionToken: ControllerSessionToken?

    init(
      profile: RemappingProfile,
      devices: [ApplicationServiceDeviceDescription],
      onPair: @escaping (ControllerSessionToken, ControllerSessionToken) -> Void
    ) {
      self.profile = profile
      self.devices = devices
      self.onPair = onPair
      _leftSessionToken = State(initialValue: Self.leftDevices(devices).first?.sessionToken)
      _rightSessionToken = State(initialValue: Self.rightDevices(devices).first?.sessionToken)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("profiles.pairJoyCons"))
          .font(.headline.weight(.semibold))
        Text(profile.name).font(.caption).foregroundColor(.secondary)
        Picker(
          OJDLocalized.string("profiles.joyConLeft"),
          selection: $leftSessionToken
        ) {
          ForEach(Self.leftDevices(devices), id: \.sessionToken) { device in
            Text(device.name + " · " + device.sessionToken.rawValue)
              .tag(Optional(device.sessionToken))
          }
        }
        Picker(
          OJDLocalized.string("profiles.joyConRight"),
          selection: $rightSessionToken
        ) {
          ForEach(Self.rightDevices(devices), id: \.sessionToken) { device in
            Text(device.name + " · " + device.sessionToken.rawValue)
              .tag(Optional(device.sessionToken))
          }
        }
        Text(
          OJDLocalized.string(
            "profiles.joyConPairSessionHint"
          )
        ).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) { dismiss() }
          Button(OJDLocalized.string("profiles.pair")) {
            if let leftSessionToken, let rightSessionToken {
              onPair(leftSessionToken, rightSessionToken)
            }
            dismiss()
          }.disabled(leftSessionToken == nil || rightSessionToken == nil)
        }
      }.padding(28).frame(width: 480)
    }

    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    private static func leftDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .left }
    }

    private static func rightDevices(
      _ devices: [ApplicationServiceDeviceDescription]
    ) -> [ApplicationServiceDeviceDescription] {
      devices.filter { JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .right }
    }
  }
#endif
