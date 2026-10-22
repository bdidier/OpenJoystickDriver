import OpenJoystickDriverKit

/// Generic raw USB facade that selects an Apple transport from ownership evidence.
///
/// Accessible vendor-specific interfaces use app-side IOUSBHost. Devices covered
/// by OJD's restricted entitlement, or currently observed behind the DEXT, use
/// USBDriverKit. An open failure never falls through to a
/// different backend.
public actor OpenJoystickDriverUSBTransportProvider: USBTransportProvider,
  USBPhysicalDeviceObservationProvider
{
  private let ioUSBHostProvider: any USBTransportProvider
  private let usbDriverKitProvider: any USBTransportProvider
  /// Reads the catalog's raw-USB models; the service changes them when user records change.
  private let rawUSBModels: @Sendable () -> Set<ControllerModelID>
  private var supportedRawUSBModels: Set<ControllerModelID> { rawUSBModels() }
  private let requiredDriverKitModels: Set<ControllerModelID>
  private let ioUSBHostObservation: @Sendable (USBTransportDevice) throws -> PhysicalDevice?
  private var signatureAdmissions: [UInt64: Bool] = [:]
  private let ioUSBHostConfigurationObservation:
    @Sendable (USBTransportDevice, UInt8) throws -> PhysicalDevice?

  /// The models OJD's restricted entitlement covers, which only the DEXT route may serve.
  static let driverKitRequiredModels = Set(
    USBDriverKitExtensionConfiguration.microsoftProductIDs.map {
      ControllerModelID(
        vendorID: USBDriverKitExtensionConfiguration.microsoftVendorID,
        productID: $0
      )
    }
  )

  public init() {
    ioUSBHostProvider = IOUSBHostTransportProvider()
    usbDriverKitProvider = USBDriverKitTransportProvider()
    let registry = ProtocolDriverRegistry()
    rawUSBModels = { Set(registry.rawUSBModels) }
    requiredDriverKitModels = Self.driverKitRequiredModels
    ioUSBHostObservation = { try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: $0) }
    ioUSBHostConfigurationObservation = Self.readConfigurationObservation
  }

  init(
    ioUSBHostProvider: any USBTransportProvider,
    usbDriverKitProvider: any USBTransportProvider,
    supportedRawUSBModels: Set<ControllerModelID>,
    requiredDriverKitModels: Set<ControllerModelID>,
    ioUSBHostObservation: @escaping @Sendable (USBTransportDevice) throws -> PhysicalDevice? = {
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: $0)
    },
    ioUSBHostConfigurationObservation:
      @escaping @Sendable (USBTransportDevice, UInt8) throws -> PhysicalDevice? =
      readConfigurationObservation
  ) {
    self.ioUSBHostProvider = ioUSBHostProvider
    self.usbDriverKitProvider = usbDriverKitProvider
    rawUSBModels = { supportedRawUSBModels }
    self.requiredDriverKitModels = requiredDriverKitModels
    self.ioUSBHostObservation = ioUSBHostObservation
    self.ioUSBHostConfigurationObservation = ioUSBHostConfigurationObservation
  }

  private static func readConfigurationObservation(
    _ device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    guard
      let descriptor = try IOUSBHostTransportProvider.cachedConfigurationDescriptor(
        of: device,
        configurationValue: configurationValue
      )
    else { return nil }
    return try PassiveUSBDescriptorProbe.physicalDeviceObservation(
      for: device,
      configurationDescriptor: descriptor
    )
  }

  public func devices() async throws -> [USBTransportDevice] {
    let direct: Result<[USBTransportDevice], Error>
    do { direct = .success(try await ioUSBHostProvider.devices()) } catch {
      direct = .failure(error)
    }
    let driverKit: Result<[USBTransportDevice], Error>
    do { driverKit = .success(try await usbDriverKitProvider.devices()) } catch {
      driverKit = .failure(error)
    }

    switch (direct, driverKit) {
    case (.failure(let directError), .failure): throw directError
    case (.success(let directDevices), .success(let driverKitDevices)):
      return Self.selectDevices(
        direct: directDevices,
        driverKit: driverKitDevices,
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels,
        signatureServiceIDs: signatureServiceIDs(in: directDevices)
      )
    case (.success(let directDevices), .failure):
      return Self.selectDevices(
        direct: directDevices,
        driverKit: [],
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels,
        signatureServiceIDs: signatureServiceIDs(in: directDevices)
      )
    case (.failure, .success(let driverKitDevices)):
      return Self.selectDevices(
        direct: [],
        driverKit: driverKitDevices,
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels
      )
    }
  }

  /// Uncatalogued direct devices whose passive facts carry a known Xbox USB signature. The DEXT
  /// matches only catalogued models, so these are reached through IOUSBHost.
  ///
  /// The decision is cached per registry service while it stays enumerated, so each poll does not
  /// re-read every device and a transient read failure cannot drop an admitted device. A negative
  /// decision is cached only once interface facts were observed; a device still being configured
  /// is looked at again.
  private func signatureServiceIDs(in direct: [USBTransportDevice]) -> Set<UInt64> {
    let enumerated = Set(direct.map(\.serviceID))
    signatureAdmissions = signatureAdmissions.filter { enumerated.contains($0.key) }
    var admitted: Set<UInt64> = []
    let supportedRawUSBModels = supportedRawUSBModels
    for device in direct {
      let model = ControllerModelID(device)
      guard !supportedRawUSBModels.contains(model), !requiredDriverKitModels.contains(model) else {
        continue
      }
      if let cached = signatureAdmissions[device.serviceID] {
        if cached { admitted.insert(device.serviceID) }
        continue
      }
      guard let observation = try? ioUSBHostObservation(device),
        observation.serviceAddress == device.serviceAddress
      else { continue }
      let carriesSignature = ProtocolDriverRegistry.carriesProtocolSignature(observation)
      if carriesSignature || !(observation.interfaces ?? []).isEmpty {
        signatureAdmissions[device.serviceID] = carriesSignature
      }
      if carriesSignature { admitted.insert(device.serviceID) }
    }
    return admitted
  }

  public func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    switch device.route {
    case .rawUSB:
      guard let observation = try? ioUSBHostObservation(device),
        observation.serviceAddress == device.serviceAddress
      else { return nil }
      return observation
    case .usbExtension: return await usbDriverKitObservation(for: device)
    }
  }

  /// Only IOUSBHost can read the device's configuration; the DEXT route reports no interfaces.
  public func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    let observation = try ioUSBHostConfigurationObservation(device, configurationValue)
    return observation?.serviceAddress == device.serviceAddress ? observation : nil
  }

  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    switch device.route {
    case .rawUSB: return try await ioUSBHostProvider.open(device, options: options)
    case .usbExtension: return try await usbDriverKitProvider.open(device, options: options)
    }
  }

  /// Only IOUSBHost devices report an exclusive owner; the DEXT route has none.
  public func exclusiveOwner(of device: USBTransportDevice) async throws -> String? {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    return try await ioUSBHostProvider.exclusiveOwner(of: device)
  }

  public func resetDevice(_ device: USBTransportDevice) async throws {
    switch device.route {
    case .rawUSB: try await ioUSBHostProvider.resetDevice(device)
    case .usbExtension: try await usbDriverKitProvider.resetDevice(device)
    }
  }

  public func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    await Task.yield()
    switch device.route {
    case .rawUSB:
      do {
        guard let observation = try ioUSBHostObservation(device),
          observation.serviceAddress == device.serviceAddress
        else { return USBTransportResolution(profile: configured) }
        let profile = Self.resolveTransportProfile(
          route: device.route,
          configured: configured,
          observation: observation
        )
        return USBTransportResolution(profile: profile, physicalDevice: observation)
      } catch {
        // Descriptor access is passive and best-effort. Opening continues with
        // the configured catalog profile when observation fails.
        return USBTransportResolution(profile: configured)
      }
    case .usbExtension:
      // DriverKit's service properties provide limited identity/route facts.
      // Do not probe the same service through direct IOUSBHost or infer an
      // interface from the extension's fixed personality.
      guard let observation = await usbDriverKitObservation(for: device) else {
        return USBTransportResolution(profile: configured)
      }
      return USBTransportResolution(profile: configured, physicalDevice: observation)
    }
  }
  static func resolveTransportProfile(
    route: USBTransportRoute,
    configured: DeviceTransportProfile,
    observation: PhysicalDevice?
  ) -> DeviceTransportProfile {
    guard route == .rawUSB, let observation else { return configured }
    return USBDescriptorTransportResolver.resolve(configured: configured, observed: observation)
  }

  public func physicalDeviceObservations() async throws -> [PhysicalDevice] {
    // Observation is deliberately best-effort. A descriptor read failure must
    // not change the exact supported-device selection or prevent diagnostics
    // from reporting devices discovered by either backend.
    let devices = try await devices()
    let hasDriverKitDevices = devices.contains { $0.route == .usbExtension }
    let driverKitObservations: [PhysicalDevice]
    if hasDriverKitDevices,
      let provider = usbDriverKitProvider as? any USBPhysicalDeviceObservationProvider
    {
      driverKitObservations = (try? await provider.physicalDeviceObservations()) ?? []
    } else {
      driverKitObservations = []
    }

    return devices.compactMap { device in
      switch device.route {
      case .rawUSB:
        guard let observation = try? ioUSBHostObservation(device),
          observation.serviceAddress == device.serviceAddress
        else { return nil }
        return observation
      case .usbExtension:
        return driverKitObservations.first { Self.driverKitObservation($0, matches: device) }
      }
    }
  }

  private func usbDriverKitObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    guard let provider = usbDriverKitProvider as? any USBPhysicalDeviceObservationProvider,
      let observations = try? await provider.physicalDeviceObservations()
    else { return nil }
    return observations.first { Self.driverKitObservation($0, matches: device) }
  }

  private static func driverKitObservation(
    _ observation: PhysicalDevice,
    matches device: USBTransportDevice
  ) -> Bool {
    observation.serviceAddress == device.serviceAddress && observation.vendorID == device.vendorID
      && observation.productID == device.productID && observation.productName == device.productName
      && observation.serialNumber == device.serialNumber
      && observation.physicalLocationIdentifier == device.observedPhysicalLocationIdentifier
  }

  static func selectDevices(
    direct: [USBTransportDevice],
    driverKit: [USBTransportDevice],
    supportedRawUSBModels: Set<ControllerModelID>,
    requiredDriverKitModels: Set<ControllerModelID>,
    signatureServiceIDs: Set<UInt64> = []
  ) -> [USBTransportDevice] {
    let observedDriverKitLocations = Set(driverKit.map(USBTransportLocation.init))
    let selectedDirect = direct.filter { device in
      (supportedRawUSBModels.contains(ControllerModelID(device))
        || signatureServiceIDs.contains(device.serviceID))
        && !requiredDriverKitModels.contains(ControllerModelID(device))
        && !observedDriverKitLocations.contains(USBTransportLocation(device))
    }
    let selectedDriverKit = driverKit.filter {
      supportedRawUSBModels.contains(ControllerModelID($0))
    }
    return (selectedDriverKit + selectedDirect).sorted(by: deviceOrder)
  }

  private static func deviceOrder(_ lhs: USBTransportDevice, _ rhs: USBTransportDevice) -> Bool {
    (lhs.vendorID, lhs.productID, lhs.locationID, lhs.route.rawValue, lhs.serviceID) < (
      rhs.vendorID, rhs.productID, rhs.locationID, rhs.route.rawValue, rhs.serviceID
    )
  }
}

extension ControllerModelID {
  /// The model of a USB device.
  init(_ device: USBTransportDevice) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }
}

private struct USBTransportLocation: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16
  let locationID: UInt32

  init(_ device: USBTransportDevice) {
    vendorID = device.vendorID
    productID = device.productID
    locationID = device.locationID
  }
}
