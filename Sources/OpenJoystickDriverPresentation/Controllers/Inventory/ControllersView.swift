#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Controllers

  struct ControllersView: View {
    @ObservedObject
    private var screen: ControllersViewModel
    let column: MainWindowColumn
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
    @State
    private var wirelessDisconnectRequest: WirelessDisconnectRequest?

    init(
      screen: ControllersViewModel,
      column: MainWindowColumn,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void
    ) {
      self.screen = screen
      self.column = column
      self.openInputTest = openInputTest
    }

    private var viewModel: RuntimeViewModel { screen.runtime }

    var body: some View {
      switch column {
      case .list: controllerList
      case .detail:
        controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity).onAppear {
          screen.refresh()
        }.onReceive(viewModel.$controllerInventoryGeneration) { _ in
          screen.synchronizeSelection()
        }
      }
    }

    private var devices: [ApplicationServiceDeviceDescription] { screen.devices }

    private var selectedDevice: ApplicationServiceDeviceDescription? { screen.selectedDevice }

    private var controllerList: some View {
      VStack(alignment: .leading, spacing: 8) {
        switch viewModel.statusState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string(
              "status.checkingControllers"
            )
          ).padding(.horizontal, 14)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.loadError"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .available:
          if let liveStatusError = screen.liveStatusError {
            ServiceFailureStateView(
              title: OJDLocalized.string(
                "controllers.loadError"
              ),
              message: liveStatusError,
              retry: refresh
            ).padding(.horizontal, 14)
          }
          if devices.isEmpty { EmptyView() } else { controllerListRows }
        }
        Spacer(minLength: 0)
      }
    }

    private var controllerListRows: some View {
      List(selection: selectedDeviceIdentifier) {
        ForEach(devices, id: \.sessionToken) { device in
          let presentation = device.publishedIdentityPresentation
          HStack(spacing: 8) {
            OJDListGlyphSlot {
              OJDSystemSymbol(
                name: presentation.controllerSymbolName,
                fallback: nil,
                fallbackSymbolName: presentation.controllerSymbolFallback
              ).foregroundColor(presentation.glyphFamily.controllerSymbolColor)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(device.name).lineLimit(1)
              Text(device.protocolBinding.displayLabel).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              ).lineLimit(1)
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(device.sessionToken.rawValue).ojdAccessibilityLabel(
            device.name
          )
          .ojdAccessibilityValue(device.protocolBinding.displayLabel)
          .contextMenu { sessionCommands(for: device) }
        }
      }.listStyle(InsetListStyle()).alert(item: $wirelessDisconnectRequest) { request in
        wirelessDisconnectAlert(for: request)
      }
    }

    /// The Controller menu's session commands for one controller.
    @ViewBuilder
    private func sessionCommands(for device: ApplicationServiceDeviceDescription) -> some View {
      if device.sessionState == .suspended {
        Button(OJDLocalized.string("mainMenu.controller.resume")) {
          Task { @MainActor in await viewModel.resumeController(device) }
        }
      } else {
        Button(OJDLocalized.string("mainMenu.controller.suspend")) {
          Task { @MainActor in await viewModel.suspendController(device) }
        }
      }
      if device.supportsWirelessDisconnect {
        Button(OJDLocalized.string("mainMenu.controller.disconnectWirelessLink")) {
          wirelessDisconnectRequest = WirelessDisconnectRequest(device: device)
        }
      }
    }

    private func wirelessDisconnectAlert(for request: WirelessDisconnectRequest) -> Alert {
      let confirmation = request.confirmation
      let device = request.device
      return Alert(
        title: Text(confirmation.title),
        message: Text(confirmation.message),
        primaryButton: .destructive(Text(confirmation.confirmTitle)) {
          Task { @MainActor in await viewModel.disconnectWirelessController(device) }
        },
        secondaryButton: .cancel()
      )
    }

    private var selectedDeviceIdentifier: Binding<String?> {
      Binding(
        get: { selectedDevice?.sessionToken.rawValue },
        set: { identifier in
          guard let identifier,
            let device = devices.first(where: { $0.sessionToken.rawValue == identifier })
          else { return }
          screen.select(device)
        }
      )
    }

    @ViewBuilder
    private var controllerDetail: some View {
      if let selectedDevice {
        ControllerDetailView(
          device: selectedDevice,
          activeProfile: activeProfileState(for: selectedDevice),
          retry: refresh,
          viewModel: viewModel,
          openInputTest: openInputTest
        ).id(selectedDevice.sessionToken.rawValue)
      } else {
        switch viewModel.statusState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string(
              "status.checkingControllers"
            )
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.loadError"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .available:
          EmptyStateView(
            symbol: "gamecontroller",
            title: OJDLocalized.string(
              "controllers.emptyTitle"
            ),
            message: OJDLocalized.string(
              "controllers.emptyMessage"
            )
          )
        }
      }
    }

    private func refresh() { screen.refresh() }

    private func activeProfileState(
      for device: ApplicationServiceDeviceDescription
    ) -> RuntimeActiveProfileState { screen.activeProfileState(for: device) }
  }

  extension VirtualIdentityGlyphFamily {
    var controllerSymbolColor: Color {
      switch self {
      case .xbox: return Color(Self.xboxBrandColor)
      case .generic: return Color(NSColor.secondaryLabelColor)
      }
    }

    private static let xboxBrandColor = NSColor(name: nil) { appearance in
      let isDark =
        appearance.bestMatch(from: [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua])
        == .darkAqua
      return NSColor(
        srgbRed: (isDark ? 155.0 : 16.0) / 255.0,
        green: (isDark ? 240.0 : 124.0) / 255.0,
        blue: (isDark ? 11.0 : 16.0) / 255.0,
        alpha: 1
      )
    }
  }

  extension ProtocolBindingID {
    /// Family label; transport variants share their family's label.
    var displayLabel: String {
      switch protocolID {
      case .xboxXID: OJDLocalized.string("controller.xboxOriginal")
      case .xboxXUSB where variant == .receiver:
        OJDLocalized.string("controller.xbox360Wireless")
      case .xboxXUSB: OJDLocalized.string("controller.xbox360")
      case .xboxGIP: OJDLocalized.string("controller.xboxOne")
      case .sonySixaxis: OJDLocalized.string("controller.dualShock3")
      case .sonyDualShock4: OJDLocalized.string("controller.dualShock4")
      case .sonyDualSense: OJDLocalized.string("controller.dualSense")
      case .valveSteamController, .valveSteamTriton, .valveSteamDeck:
        OJDLocalized.string("controller.steamController")
      case .nintendoSwitch1, .nintendoSwitch2, .nintendoSwitchInputOnly:
        OJDLocalized.string("controller.switchPro")
      case .vendorFlydigi: OJDLocalized.string("controller.flydigi")
      case .vendorPS3ThirdParty: "Third-party PS3"
      case .vendorNVIDIAShield: "NVIDIA SHIELD"
      case .vendorGameSir where variant == .usb: "GameSir G7 Pro USB"
      case .vendorGameSir: "GameSir enhanced HID"
      case .hidDescriptor, .hidReportLayout:
        OJDLocalized.string("controller.genericHID")
      }
    }
  }

  extension ApplicationServiceDeviceDescription {
    /// The identity of the virtual HID profile this controller publishes; nil when none is live.
    var publishedVirtualProfile: VirtualDeviceProfile? {
      servingDecision.selection?.profileID.identity
    }

    /// The identity shown for this controller, computed once so icon and caption always agree.
    var presentedIdentity: PresentedControllerIdentity {
      guard publication?.state == .published, let identity = publishedVirtualProfile else {
        return PresentedControllerIdentity(
          publishesVirtualDevice: false,
          presentation: protocolBinding.protocolID.physicalPresentation,
          label: physicalOwnership.isServedBySystem
            ? OJDLocalized.string("controllers.systemGamepadNotPublished")
            : RuntimePresentation.noVirtualHIDProfileLabel
        )
      }
      return PresentedControllerIdentity(
        publishesVirtualDevice: true,
        presentation: identity.presentation,
        label: identity.publishedUSBIdentityLabel
      )
    }

    var publishedIdentityPresentation: VirtualIdentityPresentation {
      presentedIdentity.presentation
    }

    var publishedIdentityLabel: String { presentedIdentity.label }

    /// The serving route of ``servingDecision``, the same route `ojd controller show` prints
    /// as `serving.route`.
    var servingRouteLabel: String {
      switch servingDecision.route {
      case .nativePassThrough: OJDLocalized.string("controllers.serving.nativePassThrough")
      case .virtualHID: OJDLocalized.string("controllers.serving.virtualHID")
      case .extensionOwned: OJDLocalized.string("controllers.serving.extensionOwned")
      case .outputDisabled: OJDLocalized.string("controllers.serving.outputDisabled")
      }
    }
  }

  /// Icon and caption of one controller: the virtual identity when OJD publishes a virtual
  /// device for it, else the physical family.
  struct PresentedControllerIdentity: Equatable {
    let publishesVirtualDevice: Bool
    let presentation: VirtualIdentityPresentation
    let label: String
  }

#endif
