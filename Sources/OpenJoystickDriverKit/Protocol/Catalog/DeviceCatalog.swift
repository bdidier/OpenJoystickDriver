import Foundation

/// The controller records the runtime binds with: the bundled catalog and any user records.
struct DeviceCatalog: Sendable {
  /// The catalog every ``ProtocolDriverRegistry`` reads. The service replaces it when the user's
  /// controller records change.
  static let current = Locked(Self())

  private let profiles: [ControllerModelID: DeviceRuntimeProfile]
  /// Each record's merged document, to tell whether a new record set changes anything.
  let documents: [ControllerModelID: Data]
  let rawUSBModels: [ControllerModelID]
  let hidModels: [ControllerModelID]

  init(records: ControllerRecordSet = .bundled) {
    var hid: [ControllerModelID] = []
    var rawUSB: [ControllerModelID] = []
    for model in records.records.keys.sorted() {
      if records.records[model]?.usesRawUSB == true {
        rawUSB.append(model)
      } else {
        hid.append(model)
      }
    }
    profiles = records.records.mapValues(\.profile)
    documents = records.records.mapValues(\.document)
    rawUSBModels = rawUSB
    hidModels = hid
  }

  /// The exact catalog record for this model; there is no default record.
  func record(for model: ControllerModelID) -> DeviceRuntimeProfile? { profiles[model] }

  /// The exact catalog record running the named mode; nil when the record does not have it.
  func record(for model: ControllerModelID, modeID: String?) -> DeviceRuntimeProfile? {
    profiles[model]?.applying(modeID: modeID)
  }

  /// Whether the record sets `server: ojd`, so OJD seizes the controller even when macOS
  /// serves it natively. The stream reads it when a device is added.
  func takesOwnership(of model: ControllerModelID) -> Bool {
    record(for: model)?.server == .ojd
  }

  /// The runtime profile for one decoded record; the record probe plan builds on it too.
  static func makeRuntimeProfile(_ record: ControllerRecordDocument) throws -> DeviceRuntimeProfile
  {
    guard (1...65_535).contains(record.vendorID), (0...65_535).contains(record.productID) else {
      throw ControllerRecordProblem(
        "invalid controller identity \(record.vendorID):\(record.productID)"
      )
    }
    let protocolInfo = record.protocolInfo
    let defaultEndpoints = protocolInfo.protocolID.protocolDescription.endpoints
    let inputEndpoint = record.usb?.endpoints?.input ?? defaultEndpoints.input
    let outputEndpoint = record.usb?.endpoints?.output ?? defaultEndpoints.output
    if record.usb != nil
      && !protocolInfo.protocolID.usesRawUSB(storedVariant: protocolInfo.protocolVariant)
    {
      throw ControllerRecordProblem("USB overrides require a raw-USB protocol family")
    }
    if let configuration = record.usb?.configuration, configuration != "set1-before-claim" {
      throw ControllerRecordProblem("unsupported USB configuration \(configuration)")
    }
    let settleMilliseconds = record.usb?.postHandshakeSettleMilliseconds ?? 0
    let keepAlivePolicy: GIPKeepAlivePolicy =
      protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled } ?? .enabled

    return DeviceRuntimeProfile(
      recordID: String(format: "%04x-%04x", record.vendorID, record.productID),
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(inputEndpoint),
        outputEndpoint: UInt8(outputEndpoint),
        hasEndpointOverride: record.usb?.endpoints != nil,
        needsSetConfiguration: record.usb?.configuration == "set1-before-claim",
        postHandshakeSettleNanoseconds: UInt64(settleMilliseconds)
          * DeviceTransportProfile.nanosecondsPerMillisecond
      ),
      physicalProtocolID: protocolInfo.protocolID,
      physicalProtocolVariant: protocolInfo.protocolVariant,
      parameters: protocolInfo.parameters,
      capabilityDelta: record.capabilities,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: protocolInfo.initialization ?? [],
      gipKeepAlivePolicy: keepAlivePolicy,
      assemblyPolicy: protocolInfo.assembly,
      server: record.server ?? .system,
      rumbleTemplate: record.rumbleTemplate,
      startupWrites: record.startupWrites,
      usbStartupWrites: record.usbStartupWrites,
      inputLayout: record.inputLayout,
      hidUsageMap: record.hidUsageMap,
      tuning: record.tuning,
      route: record.route,
      bluetoothLEVibrationCharacteristic: record.bluetoothLE?.vibrationCharacteristic,
      modes: record.modes.map(\.mode)
    )
  }

  /// The runtime profile of a row that names only this family and stored variant: default
  /// endpoints on interface 0, the default GIP initialization and keep-alive, and no parameters or
  /// capability deltas. Interface-signature bindings of uncatalogued devices run with it.
  static func familyRuntimeProfile(
    _ protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    needsSetConfiguration: Bool
  ) -> DeviceRuntimeProfile {
    let endpoints = protocolID.protocolDescription.endpoints
    return DeviceRuntimeProfile(
      recordID: nil,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(endpoints.input),
        outputEndpoint: UInt8(endpoints.output),
        needsSetConfiguration: needsSetConfiguration
      ),
      physicalProtocolID: protocolID,
      physicalProtocolVariant: protocolID.storesVariant ? variant : nil,
      parameters: .none,
      capabilityDelta: .none,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: [],
      gipKeepAlivePolicy: .enabled,
      assemblyPolicy: nil,
      server: .system,
      rumbleTemplate: nil,
      startupWrites: [],
      usbStartupWrites: [],
      inputLayout: nil,
      tuning: .none
    )
  }
}
