#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  @MainActor
  final class ControllersViewModel: ObservableObject {
    @Published
    private(set) var selectedSessionToken: String?

    let runtime: RuntimeViewModel
    private var runtimeObservation: AnyCancellable?

    init(runtime: RuntimeViewModel) {
      self.runtime = runtime
      // The list is derived from the runtime's status, so its changes must redraw this screen.
      runtimeObservation = runtime.$statusState.map { _ in () }.merge(
        with: runtime.$liveStatusError.map { _ in () }
      ).sink { [weak self] in self?.objectWillChange.send() }
    }

    var liveStatusError: String? { runtime.liveStatusError }

    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    /// Connected devices OJD does not serve, each with the reason and how to free it.
    var unservedDevices: [RuntimeUnservedDevice] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.unservedDevices
    }

    var isRefreshing: Bool { runtime.isScopedRefreshInFlight }

    var selectedDevice: ApplicationServiceDeviceDescription? {
      guard let selectedSessionToken else { return devices.first }
      return devices.first { $0.sessionToken.rawValue == selectedSessionToken } ?? devices.first
    }

    func synchronizeSelection() {
      guard let selectedSessionToken,
        devices.contains(where: { $0.sessionToken.rawValue == selectedSessionToken })
      else {
        self.selectedSessionToken = devices.first?.sessionToken.rawValue
        return
      }
    }

    func select(_ device: ApplicationServiceDeviceDescription) {
      selectedSessionToken = device.sessionToken.rawValue
    }

    /// Selects the controller with this session token, for "Show in Window".
    /// Returns false when no connected controller has it; the selection stays as it is.
    @discardableResult
    func select(sessionToken: String) -> Bool {
      guard devices.contains(where: { $0.sessionToken.rawValue == sessionToken }) else {
        return false
      }
      selectedSessionToken = sessionToken
      return true
    }

    func refresh() { Task { await runtime.refreshControllerInventory() } }

    func activeProfileState(
      for device: ApplicationServiceDeviceDescription
    ) -> RuntimeActiveProfileState {
      switch runtime.remappingState {
      case .loading: return .loading
      case .unavailable(let message): return .unavailable(message)
      case .error(let message): return .error(message)
      case .available(let snapshot):
        guard
          let profile = snapshot.activeProfiles.routingActiveProfile(
            vendorID: device.vendorID,
            productID: device.productID
          )
        else { return .noProfile }
        return .profile(profile.profileName)
      }
    }
  }

#endif
