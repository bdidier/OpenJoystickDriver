#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Controllers

  struct ControllersView: View {
    @ObservedObject
    private var screen: ControllersViewModel
    @State
    private var isRefreshing = false
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void

    init(
      screen: ControllersViewModel,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void
    ) {
      self.screen = screen
      self.openInputTest = openInputTest
    }

    private var viewModel: RuntimeViewModel { screen.runtime }

    var body: some View {
      GeometryReader { proxy in
        if WorkspaceListDetailPolicy.layout(for: proxy.size.width) == .stacked {
          VStack(spacing: 0) {
            controllerList.frame(height: min(200, proxy.size.height * 0.34))
            Divider()
            controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else {
          HStack(spacing: 0) {
            controllerList.frame(width: WorkspaceListDetailPolicy.listWidth(for: proxy.size.width))
              .frame(maxHeight: .infinity, alignment: .topLeading)
            Divider()
            controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }.onAppear { screen.refresh() }.onReceive(viewModel.$controllerInventoryGeneration) { _ in
        screen.synchronizeSelection()
      }.onReceive(viewModel.scopedRefreshInFlightPublisher.removeDuplicates()) { isRefreshing in
        self.isRefreshing = isRefreshing
      }
    }

    private var devices: [ApplicationServiceDeviceDescription] { screen.devices }

    private var selectedDevice: ApplicationServiceDeviceDescription? { screen.selectedDevice }

    private func reportedValue(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported") : trimmed
    }

    private var controllerList: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(OJDLocalized.string("common.controllers")).font(.headline)
            .lineLimit(1).layoutPriority(1)
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "arrow.clockwise",
            label: OJDLocalized.string(
              "controllers.refreshAccessibility"
            ),
            action: refresh
          ).disabled(isRefreshing)
        }.padding(.horizontal, 14).padding(.top, 18)

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
      }.background(Color(NSColor.controlBackgroundColor))
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
              Text(device.publishedIdentityLabel).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              ).lineLimit(1)
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(device.sessionToken.rawValue).ojdAccessibilityLabel(
            device.name
          )
          .ojdAccessibilityValue(
            "\(device.publishedIdentityLabel). \(device.protocolBinding.displayLabel)"
          )
        }
      }.listStyle(SidebarListStyle())
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
        )
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
          ).padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
      guard publication?.state == .published else {
        return PresentedControllerIdentity(
          publishesVirtualDevice: false,
          presentation: protocolBinding.protocolID.physicalPresentation,
          label: physicalOwnership.isServedBySystem
            ? OJDLocalized.string("controllers.nativeGamepadNotPublished")
            : RuntimePresentation.noVirtualHIDProfileLabel
        )
      }
      let identity = publishedVirtualProfile ?? VirtualHIDProfileID.generic.identity
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
      case .virtualHid: OJDLocalized.string("controllers.serving.virtualHid")
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
