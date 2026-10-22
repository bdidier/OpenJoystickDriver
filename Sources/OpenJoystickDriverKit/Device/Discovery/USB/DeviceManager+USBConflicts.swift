import Foundation

extension USBTransportProvider {
  /// Completes a raw-USB resolution from the device's own descriptor of configuration 1 when the
  /// passive registry facts carry no usable interface with endpoints: the IORegistry carries
  /// interface class triples but no endpoint descriptors, and an unconfigured device has no
  /// interfaces.
  ///
  /// The descriptor is read without SET_CONFIGURATION, and claimed-interface validation checks it
  /// before any write. The pipeline's open sends the only SET_CONFIGURATION: rows that set it
  /// before the claim already request it, and a device observed unconfigured gets it too, since
  /// none of its interfaces can be claimed otherwise. Explicit catalog endpoint pins stay
  /// authoritative, but a pinned device is read too, so validation can confirm its interface class
  /// and that the pinned endpoints exist. Returns nil when the descriptor cannot be read, so a
  /// later poll retries instead of running on unvalidated or family-default endpoints.
  ///
  /// - Throws: ``USBTransportError/accessDenied`` when the host refuses the read because another
  ///   owner holds the device. The refusal does not clear on its own, so the caller names it
  ///   instead of retrying.
  public func resolveUSBConfiguration(
    _ device: USBTransportDevice,
    passive: USBTransportResolution
  ) async throws(USBTransportError) -> USBTransportResolution? {
    let configured = settingConfigurationIfUnconfigured(
      passive.profile,
      observed: passive.physicalDevice
    )
    let passiveResolution = USBTransportResolution(
      profile: configured,
      physicalDevice: passive.physicalDevice
    )
    guard device.route == .rawUSB,
      USBDescriptorTransportResolver.discover(
        configured: configured,
        observed: passive.physicalDevice
      ) == nil
    else { return passiveResolution }
    do {
      guard let observed = try await configurationObservation(for: device, configurationValue: 1)
      else {
        print("[USBTransport] USB configuration descriptor unavailable for \(device.serviceID)")
        return nil
      }
      return USBTransportResolution(
        profile: USBDescriptorTransportResolver.resolve(configured: configured, observed: observed),
        physicalDevice: observed
      )
    } catch USBTransportError.notSupported {
      // The provider has no descriptor source; the passive facts are all there is.
      return passiveResolution
    } catch USBTransportError.accessDenied {
      throw .accessDenied
    } catch {
      print(
        "[USBTransport] USB configuration descriptor read failed for \(device.serviceID): \(error)"
      )
      return nil
    }
  }
}

private func settingConfigurationIfUnconfigured(
  _ profile: DeviceTransportProfile,
  observed: PhysicalDevice?
) -> DeviceTransportProfile {
  guard !profile.needsSetConfiguration, let observed, (observed.interfaces ?? []).isEmpty,
    (observed.configurationValue ?? 0) == 0
  else { return profile }
  return DeviceTransportProfile(
    inputEndpoint: profile.inputEndpoint,
    outputEndpoint: profile.outputEndpoint,
    interfaceNumber: profile.interfaceNumber,
    alternateSetting: profile.alternateSetting,
    hasInterfaceOverride: profile.hasInterfaceOverride,
    hasEndpointOverride: profile.hasEndpointOverride,
    needsSetConfiguration: true,
    postHandshakeSettleNanoseconds: profile.postHandshakeSettleNanoseconds
  )
}

extension DeviceManager {
  /// The logical-controller key of a raw-USB service claiming the profile's interface.
  static func usbIdentifier(
    for device: USBTransportDevice,
    claiming profile: DeviceTransportProfile
  ) -> LogicalControllerID {
    LogicalControllerID(
      vendorID: device.vendorID,
      productID: device.productID,
      serialNumber: device.serialNumber,
      locationID: device.locationID,
      interfaceNumber: profile.interfaceNumber
    )
  }

  /// With `yieldingHID`, a HID pipeline of the same controller is not a conflict, because
  /// `yieldHIDPipelines(to:)` stops it before the raw-USB pipeline starts. A native pass-through
  /// HID controller is never yielded.
  func hasUSBPipelineConflict(
    for identifier: LogicalControllerID,
    service: ControllerConnectionAddress,
    yieldingHID: Bool = false
  ) -> Bool {
    Self.hasUSBPipelineConflict(
      for: identifier,
      service: service,
      among: pipelines.keys.filter { !yieldingHID || !yieldsToRawUSB($0) }.map {
        ($0, deviceInfos[$0]?.usbTransportDevice?.serviceAddress)
      }
    )
  }

  private func yieldsToRawUSB(_ key: LogicalControllerID) -> Bool {
    guard let info = deviceInfos[key], case .hid = info.discoverySource else { return false }
    return info.physicalDevice?.nativePassThrough != true
  }

  /// Raw USB takes precedence over HID for a controller reachable by both, so the route does not
  /// depend on which admission ran first. Stops each HID pipeline that serves the same physical
  /// controller as `identifier` and releases its input claim, leaving the device unseized.
  func yieldHIDPipelines(to identifier: LogicalControllerID) async {
    let yielded = deviceInfos.keys.filter {
      yieldsToRawUSB($0) && Self.isSamePhysicalController($0, identifier)
    }
    for key in yielded {
      print("[DeviceManager] Raw USB takes precedence over HID for \(key)")
      if let info = deviceInfos[key], let physicalDevice = info.physicalDevice,
        let connectionID = info.hidConnectionID, let address = key.hidRoutingAddress
      {
        yieldedHIDConnections[connectionID] = YieldedHIDConnection(
          identifier: key,
          snapshot: HIDDeviceConnectionSnapshot(
            connection: HIDDeviceConnection(
              connectionID: connectionID,
              physicalDevice: physicalDevice,
              routingAddress: address
            ),
            ownership: info.hidInputOwnership
          )
        )
      }
      await tearDownHIDDevice(identifier: key)
      if let address = key.hidRoutingAddress {
        _ = await hidManager.releaseInputClaim(address: address)
      }
    }
  }

  /// Whether a native pass-through HID controller serves the same physical controller as
  /// `identifier`. macOS serves it, so raw USB does not claim it.
  func hasNativeHIDController(sameAs identifier: LogicalControllerID) -> Bool {
    deviceInfos.contains { key, info in
      guard case .hid = info.discoverySource, info.physicalDevice?.nativePassThrough == true else {
        return false
      }
      return Self.isSamePhysicalController(key, identifier)
    }
  }

  /// Leaves a raw-USB service unclaimed while a native HID controller serves its controller. The
  /// caller acknowledges the service, so the poll does not retry it or repeat the log line;
  /// `releaseNativeShadowedUSBServices(in:)` admits it again once the native controller is gone.
  func deferToNativeHID(_ device: USBTransportDevice, identifier: LogicalControllerID) -> Bool {
    guard hasNativeHIDController(sameAs: identifier) else { return false }
    if nativeShadowedUSBServices.updateValue(identifier, forKey: device.serviceAddress) == nil {
      print("[DeviceManager] Native HID serves \(identifier); raw USB left unclaimed")
    }
    return true
  }

  /// Makes the polling loop attach a shadowed service again once no native HID controller serves
  /// its controller, while the USB device stays attached.
  func releaseNativeShadowedUSBServices(in enumeration: inout USBEnumerationTracker) {
    for (service, identifier) in nativeShadowedUSBServices
    where !hasNativeHIDController(sameAs: identifier) {
      nativeShadowedUSBServices.removeValue(forKey: service)
      if let device = enumeration.acknowledgedDevices[service] { enumeration.unacknowledge(device) }
    }
  }

  /// Leaves a raw-USB service unclaimed because another owner holds the device and the host
  /// refused to read its configuration. The caller acknowledges the service, so the poll does not
  /// retry it; the log line and the unbound record appear once per attachment.
  /// `releaseHeldUSBServices(in:provider:)` admits it again when the host stops reporting the
  /// owner it reported here, and a re-enumeration admits it as a new attachment.
  func holdForOwner(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider,
    interfaces: [PhysicalInterfaceSignature]
  ) async {
    let owner: String?
    let ownerNote: String
    do {
      owner = try await provider.exclusiveOwner(of: device)
      ownerNote = owner.map { "held by \($0)" } ?? "the host reports no exclusive owner"
    } catch {
      owner = nil
      ownerNote = "the host owner cannot be read (\(error))"
    }
    heldUSBServices[device.serviceAddress] = HeldUSBService(owner: owner)
    print(
      "[DeviceManager] USB device \(device.serviceID) refused the configuration read: "
        + "\(ownerNote); left unclaimed until it re-enumerates"
        + (owner == nil ? "" : " or its owner releases it")
    )
    recordUnboundDevice(
      .usb(device.serviceAddress),
      vendorID: device.vendorID,
      productID: device.productID,
      connection: "USB",
      backend: DeviceAccessBackend(route: device.route),
      reason: .deviceInUse,
      rejectedCandidates: [],
      interfaces: interfaces
    )
  }

  /// Makes the polling loop attach a held service again once the host no longer reports the
  /// exclusive owner it reported when the service was held. A service held without a reported
  /// owner, or whose owner cannot be read, stays held until it re-enumerates.
  func releaseHeldUSBServices(
    in enumeration: inout USBEnumerationTracker,
    provider: any USBTransportProvider
  ) async {
    for (service, held) in heldUSBServices where held.owner != nil {
      guard let device = enumeration.acknowledgedDevices[service] else { continue }
      let current: String?
      do { current = try await provider.exclusiveOwner(of: device) } catch { continue }
      guard current == nil, heldUSBServices.removeValue(forKey: service) != nil else { continue }
      clearUnboundDevice(.usb(service))
      enumeration.unacknowledge(device)
    }
  }

  /// Native pass-through wins over raw USB for a controller reachable by both, so the route does
  /// not depend on which admission ran first. Removes and stops each raw-USB pipeline of the
  /// same physical controller as `identifier`, which closes its USB claim, and drops the HID
  /// connections that had yielded to them. The service stays acknowledged and is remembered as
  /// shadowed, so it is admitted again if the native controller goes away.
  func yieldRawUSBPipelines(toNative identifier: LogicalControllerID) async {
    let raw = deviceInfos.filter { key, info in
      info.usbTransportDevice != nil && Self.isSamePhysicalController(key, identifier)
    }
    guard !raw.isEmpty else { return }
    for (key, info) in raw {
      print("[DeviceManager] Native HID takes precedence over raw USB for \(key)")
      if let service = info.usbTransportDevice?.serviceAddress {
        nativeShadowedUSBServices[service] = key
      }
    }
    yieldedHIDConnections = yieldedHIDConnections.filter {
      !Self.isSamePhysicalController($0.value.identifier, identifier)
    }
    let removed = raw.keys.compactMap(removeUSBRole)
    notifyServiceStatusChanged()
    for pipeline in removed { await pipeline.stop() }
  }

  /// Polls with every raw-USB pipeline of a yielded controller still failing to start a session
  /// before its HID route returns, so one transient failure does not flap the route.
  private static let yieldedHIDRestoreFailedPolls = 2

  /// Restores the HID route of a yielded controller whose raw-USB session never starts. The
  /// raw-USB pipelines are removed and stopped, and the HID connection is admitted again. The
  /// USB service stays acknowledged, so raw USB is not retried until the device re-enumerates.
  func restoreYieldedHIDRoutes() async {
    for connectionID in Array(yieldedHIDConnections.keys) {
      guard var yielded = yieldedHIDConnections[connectionID] else { continue }
      let raw = pipelines.filter {
        deviceInfos[$0.key]?.usbTransportDevice != nil
          && Self.isSamePhysicalController($0.key, yielded.identifier)
      }
      var allFailed = !raw.isEmpty
      for pipeline in raw.values where allFailed {
        allFailed = await pipeline.usbSessionStartFailed
      }
      // The awaits above suspend the actor; act only on the pipelines that were just observed.
      guard allFailed, yieldedHIDConnections[connectionID] != nil,
        raw.allSatisfy({ pipelines[$0.key] === $0.value })
      else {
        yieldedHIDConnections[connectionID]?.failedPolls = 0
        continue
      }
      yielded.failedPolls += 1
      yieldedHIDConnections[connectionID] = yielded
      guard yielded.failedPolls >= Self.yieldedHIDRestoreFailedPolls else { continue }
      print(
        "[DeviceManager] Raw USB session never started; restoring HID for \(yielded.identifier)"
      )
      let removed = raw.keys.compactMap { key in removeUSBRole(key).map { (key, $0) } }
      notifyServiceStatusChanged()
      for (_, pipeline) in removed { await pipeline.stop() }
      guard !isStopping, yieldedHIDConnections[connectionID] != nil else { continue }
      yieldedHIDConnections.removeValue(forKey: connectionID)
      let connection = yielded.snapshot.connection
      _ = await hidManager.reacquireInputClaim(address: connection.routingAddress)
      scheduleHIDDeviceInitialization(connection: connection, ownership: yielded.snapshot.ownership)
      await reconcileUnboundHIDClaims()
    }
  }

  /// A raw-USB admission conflicts when its exact logical-controller key is already running, or
  /// when the same physical controller runs through another service: another route, another
  /// location, or HID, whose pipelines carry no service. Interfaces of one service never conflict
  /// with each other, so each receiver slot can hold its own pipeline.
  static func hasUSBPipelineConflict(
    for identifier: LogicalControllerID,
    service: ControllerConnectionAddress,
    among pipelines: [(key: LogicalControllerID, service: ControllerConnectionAddress?)]
  ) -> Bool {
    pipelines.contains { key, keyService in
      key == identifier || keyService != service && isSamePhysicalController(key, identifier)
    }
  }

  /// Whether two keys reached through different services belong to one physical controller: the
  /// same identity with a serial number, or, since a serial-less identity names only a model, the
  /// same identity at the same location. A USB device's HID interfaces report its USB location.
  static func isSamePhysicalController(
    _ lhs: LogicalControllerID,
    _ rhs: LogicalControllerID
  ) -> Bool {
    lhs.hardware == rhs.hardware
      && (lhs.hardware.identifiesPhysicalDevice
        || lhs.address?.locationID == rhs.address?.locationID)
  }

  /// The running raw-USB pipeline that serves the same physical controller as a HID key, if any.
  func rawUSBIdentifier(
    servingSameControllerAs identifier: LogicalControllerID
  ) -> LogicalControllerID? {
    pipelines.keys.first {
      deviceInfos[$0]?.usbTransportDevice != nil && Self.isSamePhysicalController($0, identifier)
    }
  }
}

/// A raw-USB service held by another owner. `owner` is the exclusive owner the host reported when
/// the service was held; nil when it reported none.
struct HeldUSBService: Equatable {
  let owner: String?
}

/// A HID connection stopped for a raw-USB pipeline of its controller, with the key it ran under.
struct YieldedHIDConnection {
  let identifier: LogicalControllerID
  let snapshot: HIDDeviceConnectionSnapshot
  var failedPolls = 0
}
