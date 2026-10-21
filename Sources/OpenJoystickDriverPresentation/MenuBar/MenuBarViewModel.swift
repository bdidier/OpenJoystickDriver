#if canImport(AppKit)

  import Foundation
  import OpenJoystickDriverKit

  @MainActor
  final class MenuBarViewModel {
    let runtime: RuntimeViewModel
    private let localization: Localization

    init(runtime: RuntimeViewModel, localization: Localization = Localization()) {
      self.runtime = runtime
      self.localization = localization
    }

    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    var needsPermissionAttention: Bool {
      guard case .available(let status) = runtime.statusState else { return false }
      let needsPostEventAccess =
        status.requiresPostEventAccess == true && status.postEventAccess != .granted
      return !status.permissions.isReady || needsPostEventAccess
    }

    var summaryTitle: String {
      let readiness: String
      let controllerSummary: String
      switch runtime.statusState {
      case .loading:
        readiness = OJDLocalized.string("status.starting")
        controllerSummary = RuntimePresentation.deviceCountLabel(0)
      case .available(let status):
        readiness = status.readinessLabel
        controllerSummary = status.deviceCountLabel
      case .unavailable, .error:
        readiness = OJDLocalized.string("common.needsAttention")
        controllerSummary = RuntimePresentation.deviceCountLabel(0)
      }

      let profileSummary: String
      if case .available(let snapshot) = runtime.remappingState,
        let activeProfile = snapshot.activeProfiles.last(where: { $0.applicationScope == .global })
          ?? snapshot.activeProfiles.last,
        let profile = snapshot.profiles.first(where: { $0.id == activeProfile.profileID })
      {
        profileSummary = profile.name
      } else {
        profileSummary = OJDLocalized.string(
          "status.noActiveProfile"
        )
      }
      return StatusItemStatusLine.make(
        readiness: readiness,
        controllers: controllerSummary,
        profile: profileSummary,
        localization: localization,
        locale: .current
      )
    }

    var statusItemState: StatusItemState {
      var profiles: [StatusItemState.Profile] = []
      var snapshot: ApplicationServiceRemappingSnapshotPayload?
      if case .available(let available) = runtime.remappingState {
        snapshot = available
      }
      if let snapshot {
        let activeIDs = Set(snapshot.activeProfiles.map(\.profileID))
        profiles = snapshot.profiles.map {
          StatusItemState.Profile(id: $0.id, name: $0.name, isActive: activeIDs.contains($0.id))
        }
      }
      return StatusItemState(
        statusLine: summaryTitle,
        needsAccess: needsPermissionAttention,
        controllers: devices.map {
          StatusItemState.Controller(
            id: $0.sessionToken.rawValue,
            name: $0.name,
            isSuspended: $0.sessionState == .suspended,
            isWireless: $0.supportsWirelessDisconnect,
            profiles: Self.profiles(applyingTo: $0, in: snapshot)
          )
        },
        profiles: profiles,
        statusSymbolName: summarySemanticState.presentation.symbolName
      )
    }

    /// The profiles of the snapshot that apply to the controller: its model, and its unit when
    /// the profile names one. The active one is the profile routing uses for the controller's
    /// model.
    static func profiles(
      applyingTo device: ApplicationServiceDeviceDescription,
      in snapshot: ApplicationServiceRemappingSnapshotPayload?
    ) -> [StatusItemState.Profile] {
      guard let snapshot else { return [] }
      let activeID = snapshot.activeProfiles.routingActiveProfile(
        vendorID: device.vendorID,
        productID: device.productID
      )?.profileID
      return snapshot.profiles.filter {
        $0.device.vendorID == device.vendorID && $0.device.productID == device.productID
          && ($0.device.unit == nil || $0.device.unit == device.portKey?.rawValue)
      }.map { StatusItemState.Profile(id: $0.id, name: $0.name, isActive: $0.id == activeID) }
    }

    var summarySemanticState: SemanticState {
      switch runtime.statusState {
      case .loading: return .loading
      case .available(let status): return status.readiness == .ready ? .healthy : .attention
      case .unavailable, .error: return .failure
      }
    }

    func refresh() async {
      await runtime.refreshSystemExtensionSetup()
      await runtime.refresh()
    }

    func refreshLiveStatus() async -> Bool { await runtime.refreshLiveStatus() }
  }

#endif
