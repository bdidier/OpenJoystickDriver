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
      if case .available(let snapshot) = runtime.remappingState {
        let activeIDs = Set(snapshot.activeProfiles.map(\.profileID))
        profiles = snapshot.profiles.map {
          StatusItemState.Profile(id: $0.id, name: $0.name, isActive: activeIDs.contains($0.id))
        }
      }
      return StatusItemState(
        statusLine: summaryTitle,
        controllers: devices.map {
          StatusItemState.Controller(
            id: $0.sessionToken.rawValue,
            name: $0.name,
            isSuspended: $0.sessionState == .suspended,
            isWireless: $0.supportsWirelessDisconnect
          )
        },
        profiles: profiles,
        statusSymbolName: summarySemanticState.presentation.symbolName
      )
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
