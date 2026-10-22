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
              "ui.controllers.unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.controllers.loadError"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .available:
          if let liveStatusError = screen.liveStatusError {
            ServiceFailureStateView(
              title: OJDLocalized.string(
                "ui.controllers.loadError"
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
              Text(device.protocolBinding.displayName).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              ).lineLimit(1)
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(device.sessionToken.rawValue).ojdAccessibilityLabel(
            device.name
          )
          .ojdAccessibilityValue(device.protocolBinding.displayName)
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
        Button(OJDLocalized.string("ui.menu.controller.resume")) {
          Task { @MainActor in await viewModel.resumeController(device) }
        }
      } else {
        Button(OJDLocalized.string("ui.menu.controller.suspend")) {
          Task { @MainActor in await viewModel.suspendController(device) }
        }
      }
      if device.supportsWirelessDisconnect {
        Button(OJDLocalized.string("ui.menu.controller.disconnectWirelessLink")) {
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
              "ui.controllers.unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.controllers.loadError"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .available:
          EmptyStateView(
            symbol: "gamecontroller",
            title: OJDLocalized.string(
              "ui.controllers.emptyTitle"
            ),
            message: OJDLocalized.string(
              "ui.controllers.emptyMessage"
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
            ? OJDLocalized.string("platform.macos.ui.controllers.systemGamepadNotPublished")
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
      case .nativePassThrough:
        OJDLocalized.string("platform.macos.ui.controllers.serving.nativePassThrough")
      case .virtualHID: OJDLocalized.string("ui.controllers.serving.virtualHID")
      case .extensionOwned: OJDLocalized.string("ui.controllers.serving.extensionOwned")
      case .outputDisabled: OJDLocalized.string("ui.controllers.serving.outputDisabled")
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
