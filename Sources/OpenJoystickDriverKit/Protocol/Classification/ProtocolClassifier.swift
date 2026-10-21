import Foundation

/// Physical protocol families with an implemented OJD parser.
///
/// The taxonomy in the protocol specification names more families; a family joins
/// this enum only when a driver for it exists.
public enum PhysicalProtocolID: String, CaseIterable, Codable, Sendable {
  case hidDescriptor = "HIDDescriptor"
  /// A fixed input-report layout from the controller record (``ControllerInputLayout``).
  case hidReportLayout = "HIDReportLayout"
  case xboxXID = "XboxXID"
  case xboxXUSB = "XboxXUSB"
  case xboxGIP = "XboxGIP"
  case sonySixaxis = "SonySixaxis"
  case sonyDualShock4 = "SonyDualShock4"
  case sonyDualSense = "SonyDualSense"
  case nintendoSwitch1 = "NintendoSwitch1"
  /// Nintendo Switch 2 controller (SDL `SDL_hidapi_switch2.c`): input report `0x05` after an init
  /// sequence on the vendor bulk interface, or the same state over its Bluetooth LE GATT link.
  case nintendoSwitch2 = "NintendoSwitch2"
  /// Wired Switch pad with a fixed HID input report and no subcommand channel (SDL
  /// `SwitchInputOnlyController`).
  case nintendoSwitchInputOnly = "NintendoSwitchInputOnly"
  case valveSteamController = "ValveSteamController"
  /// 2026 Steam Controller (SDL `SteamControllerTriton`): its own report IDs, settings feature
  /// report, and repeated rumble report.
  case valveSteamTriton = "ValveSteamTriton"
  /// Steam Deck built-in controller (SDL `SteamControllerNeptune`): its own state report,
  /// settings, watchdog, and rumble report.
  case valveSteamDeck = "ValveSteamDeck"
  case vendorFlydigi = "VendorFlydigi"
  case vendorPS3ThirdParty = "VendorPS3ThirdParty"
  case vendorGameSir = "VendorGameSir"
  case vendorNVIDIAShield = "VendorNVIDIAShield"

  /// The stem of this family's description file in `Resources/Protocols`: lowercase kebab-case
  /// with each brand or product name kept as one word.
  public var descriptionFileStem: String {
    switch self {
    case .hidDescriptor: "hid-descriptor"
    case .hidReportLayout: "hid-report-layout"
    case .xboxXID: "xbox-xid"
    case .xboxXUSB: "xbox-xusb"
    case .xboxGIP: "xbox-gip"
    case .sonySixaxis: "sony-sixaxis"
    case .sonyDualShock4: "sony-dualshock4"
    case .sonyDualSense: "sony-dualsense"
    case .nintendoSwitch1: "nintendo-switch1"
    case .nintendoSwitch2: "nintendo-switch2"
    case .nintendoSwitchInputOnly: "nintendo-switch-input-only"
    case .valveSteamController: "valve-steam-controller"
    case .valveSteamTriton: "valve-steam-triton"
    case .valveSteamDeck: "valve-steam-deck"
    case .vendorFlydigi: "vendor-flydigi"
    case .vendorPS3ThirdParty: "vendor-ps3-third-party"
    case .vendorGameSir: "vendor-gamesir"
    case .vendorNVIDIAShield: "vendor-nvidia-shield"
    }
  }

  /// Implemented variants, as the family's description lists them. An empty list means the family
  /// has one contract.
  public var variants: [PhysicalProtocolVariantID] { protocolDescription.variants }

  /// Whether rows of this family, with this stored variant, are reached through raw USB.
  public func usesRawUSB(storedVariant: PhysicalProtocolVariantID?) -> Bool {
    protocolDescription.rawUSB.applies(to: storedVariant)
  }

  /// This family's bundled protocol description, which holds the facts its driver reads.
  var protocolDescription: ProtocolDescription {
    guard let description = ProtocolDescription.bundled[self] else {
      fatalError("[ProtocolDescription] No description for \(rawValue)")
    }
    return description
  }

  /// Whether this family's driver encodes rumble from a record's rumble template.
  var encodesRumbleTemplate: Bool { protocolDescription.recordSections.contains(.rumble) }

  /// Whether the driver of this family, stored variant and parameters encodes rumble from a
  /// record's rumble template: the family reads one, and GameSir reads it only for enhanced HID
  /// and NVIDIA SHIELD only for the 2015 controller.
  func readsRecordRumbleTemplate(
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> Bool {
    guard encodesRumbleTemplate else { return false }
    switch self {
    case .vendorGameSir: return variant == .enhancedHID
    case .vendorNVIDIAShield: return parameters.reportRevision == .shield2015
    default: return true
    }
  }

  /// Whether records of this family need an input layout of their own: the driver reads one and
  /// the description supplies none.
  var requiresRecordInputLayout: Bool {
    let description = protocolDescription
    return description.recordSections.contains(.input) && description.inputLayout == nil
  }

  /// Whether catalog records store this family's variant, as the family's description says;
  /// otherwise the family has one contract or classification derives the variant from the
  /// observed transport.
  public var storesVariant: Bool { protocolDescription.storesVariant }
}

/// Protocol variants. Transport variants are derived from the observed transport;
/// catalog records store only variants that transport cannot decide
/// (``PhysicalProtocolID/storesVariant``).
public enum PhysicalProtocolVariantID: String, CaseIterable, Sendable {
  case usb = "USB"
  case bluetoothClassic = "BluetoothClassic"
  case bluetoothLE = "BluetoothLE"
  case gamepad = "Gamepad"
  case wired = "Wired"
  case receiver = "Receiver"
  case dongle = "Dongle"
  case enhancedHID = "EnhancedHID"
}

/// Machine-readable reasons a device is not bound.
public enum ProtocolBindingReason: String, CaseIterable, Codable, Error, Sendable {
  case noProtocolMatch = "NoProtocolMatch"
  case ambiguousProtocolMatch = "AmbiguousProtocolMatch"
  case interfaceContractMismatch = "InterfaceContractMismatch"
  case descriptorContractMismatch = "DescriptorContractMismatch"
  case packetContractMismatch = "PacketContractMismatch"
  case unsupportedProtocolVariant = "UnsupportedProtocolVariant"
  case unsupportedTransportVariant = "UnsupportedTransportVariant"
  case requiredInitializationFailed = "RequiredInitializationFailed"
  case catalogConflict = "CatalogConflict"
  case virtualProfileUnavailable = "VirtualProfileUnavailable"
}

/// Observed facts that supported a binding.
public enum ProtocolPredicate: String, Codable, Sendable {
  case catalogIdentity = "CatalogIdentity"
  case catalogAccessPath = "CatalogAccessPath"
  case hostTransport = "HostTransport"
  case interfaceSignature = "InterfaceSignature"
  /// The device descriptor's class triple on an unconfigured device with no interface facts.
  case deviceClassSignature = "DeviceClassSignature"
  case interruptEndpointPair = "InterruptEndpointPair"
  case hidDescriptorContract = "HIDDescriptorContract"
}

/// One selected protocol for one physical device.
public struct ProtocolBinding: Equatable, Sendable {
  public enum Rule: String, Codable, Sendable {
    case catalogRecord = "CatalogRecord"
    case interfaceSignature = "InterfaceSignature"
    case hidDescriptor = "HIDDescriptor"
  }

  public let protocolID: PhysicalProtocolID
  public let variant: PhysicalProtocolVariantID?
  public let accessBackend: DeviceAccessBackend
  public let interfaceNumber: UInt8?
  public let rule: Rule
  public let matchedPredicates: [ProtocolPredicate]
  public let record: DeviceRuntimeProfile?

  public var id: ProtocolBindingID { ProtocolBindingID(protocolID, variant: variant) }
}

public enum ProtocolClassification: Equatable, Sendable {
  case bound(ProtocolBinding)
  /// `rejected` names the family that matched and then failed its contract; nil when none matched.
  case unsupported(ProtocolBindingReason, rejected: ProtocolBindingResult.RejectedCandidate? = nil)
  case conflict(ProtocolBindingReason, candidates: [PhysicalProtocolID])
}

/// Deterministic protocol selection from observed facts. It performs no I/O.
///
/// Precedence: exact catalog record, then a protocol-standard USB interface
/// signature (the device-descriptor GIP triple only when an unconfigured device
/// exposes no interface facts), then the `HIDDescriptor` contract.
/// `HIDDescriptor` always requires the descriptor contract, including for catalog records.
/// A validation failure never falls through to a lower level. One exception: a record of one
/// Xbox USB family whose device exposes only the other family's interface signature binds by
/// that signature.
enum ProtocolClassifier {
  static func classify(
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend,
    catalog: DeviceCatalog,
    modeID: String? = nil
  ) -> ProtocolClassification {
    let interfaces = (device.interfaces ?? []).sorted {
      ($0.interfaceNumber ?? .max, $0.alternateSetting ?? .max) < (
        $1.interfaceNumber ?? .max, $1.alternateSetting ?? .max
      )
    }
    if let vendorID = device.vendorID, let productID = device.productID,
      let record = catalog.record(
        for: ControllerModelID(vendorID: vendorID, productID: productID),
        modeID: modeID
      )
    {
      return otherXboxFamilyBinding(for: record, interfaces: interfaces, backend: backend)
        ?? bind(record, interfaces: interfaces, backend: backend)
    }
    if let result = classifySignature(interfaces, backend: backend)
      ?? classifyDeviceSignature(device, backend: backend)
    {
      return result
    }
    guard !backend.usesRawUSB else { return .unsupported(.noProtocolMatch) }
    guard let interface = descriptorInterface(interfaces) else {
      return .unsupported(.descriptorContractMismatch)
    }
    return .bound(
      ProtocolBinding(
        protocolID: .hidDescriptor,
        variant: nil,
        accessBackend: backend,
        interfaceNumber: interface.interfaceNumber,
        rule: .hidDescriptor,
        matchedPredicates: [.hidDescriptorContract],
        record: nil
      )
    )
  }

  private static func bind(
    _ record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification {
    let isRawUSB = backend.usesRawUSB
    func reject(_ reason: ProtocolBindingReason) -> ProtocolClassification {
      .unsupported(
        reason,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: record.physicalProtocolID,
          reason: reason,
          catalogRecordID: record.recordID
        )
      )
    }
    guard record.usesRawUSB == isRawUSB else { return reject(.unsupportedTransportVariant) }
    var predicates: [ProtocolPredicate] = [.catalogIdentity, .catalogAccessPath]
    let variants = transportVariants(of: record)
    let variant: PhysicalProtocolVariantID?
    if let stored = record.physicalProtocolVariant {
      variant = stored
    } else if variants.isEmpty {
      variant = nil
    } else {
      let observed = isRawUSB ? .usb : hostTransportVariant(interfaces)
      guard let observed, variants.contains(observed) else {
        return reject(.unsupportedTransportVariant)
      }
      variant = observed
      predicates.append(.hostTransport)
    }
    var interfaceNumber =
      isRawUSB
      ? record.transportProfile.interfaceNumber
      : boundInterfaceNumber(of: record, in: interfaces)
    // A catalog row adds identity to `HIDDescriptor`; it never replaces validation.
    if record.physicalProtocolID == .hidDescriptor {
      guard let interface = descriptorInterface(interfaces) else {
        return reject(.descriptorContractMismatch)
      }
      interfaceNumber = interface.interfaceNumber
      predicates.append(.hidDescriptorContract)
    }
    return .bound(
      ProtocolBinding(
        protocolID: record.physicalProtocolID,
        variant: variant,
        accessBackend: backend,
        interfaceNumber: interfaceNumber,
        rule: .catalogRecord,
        matchedPredicates: predicates,
        record: record
      )
    )
  }

  /// The signature binding of a device whose record names one Xbox USB family but whose
  /// interfaces carry only the other's. One VID:PID can ship either firmware mode (8BitDo
  /// `2dc8:3106` is XUSB in Linux `xpad.c` and GIP in SDL `controller_list.h`), and the claimed
  /// interface class is what the device speaks. Nil when the record's own signature is present.
  private static func otherXboxFamilyBinding(
    for record: DeviceRuntimeProfile,
    interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    let xboxUSB: Set<PhysicalProtocolID> = [.xboxXUSB, .xboxGIP]
    guard xboxUSB.contains(record.physicalProtocolID) else { return nil }
    let observed = Set(
      signatures.filter { signature in interfaces.contains(where: signature.matches) }.map(
        \.protocolID
      )
    )
    guard !observed.contains(record.physicalProtocolID),
      !observed.isDisjoint(with: xboxUSB.subtracting([record.physicalProtocolID]))
    else { return nil }
    return classifySignature(interfaces, backend: backend)
  }

  /// The first interface whose observed HID facts satisfy the descriptor contract.
  /// The interface a HID record binds to: the lowest one inside the mode's `interface` range, or
  /// the only one when the record names no range.
  private static func boundInterfaceNumber(
    of record: DeviceRuntimeProfile,
    in interfaces: [PhysicalInterfaceSignature]
  ) -> UInt8? {
    guard let range = record.interfaceRange else {
      return interfaces.count == 1 ? interfaces[0].interfaceNumber : nil
    }
    return interfaces.compactMap(\.interfaceNumber).filter(range.contains).min()
  }

  private static func descriptorInterface(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalInterfaceSignature? {
    interfaces.first { HIDDescriptorContract.violation(in: $0.hidLayout) == nil }
  }

  /// The family's variants this model has a link for: all of them, except for a Bluetooth-only
  /// Switch pad, whose USB link only charges it.
  private static func transportVariants(
    of record: DeviceRuntimeProfile
  ) -> [PhysicalProtocolVariantID] {
    let variants = record.physicalProtocolID.variants
    guard record.parameters.usbProtocol == .chargingOnly else { return variants }
    return variants.filter { $0 != .usb }
  }

  /// The single host transport shared by every interface; unknown when any is absent.
  private static func hostTransportVariant(
    _ interfaces: [PhysicalInterfaceSignature]
  ) -> PhysicalProtocolVariantID? {
    guard let transport = interfaces.first?.hostTransport,
      interfaces.allSatisfy({ $0.hostTransport == transport })
    else { return nil }
    switch transport {
    case .usb: return .usb
    case .bluetoothClassic: return .bluetoothClassic
    case .bluetoothLE: return .bluetoothLE
    case .proprietaryRadioReceiver: return nil
    }
  }

  private static func classifySignature(
    _ interfaces: [PhysicalInterfaceSignature],
    backend: DeviceAccessBackend
  ) -> ProtocolClassification? {
    var matched: [ProtocolInterfaceSignature] = []
    for interface in interfaces {
      for signature in signatures where signature.matches(interface) && !matched.contains(signature)
      { matched.append(signature) }
    }
    guard let signature = matched.first else { return nil }
    var candidates: [PhysicalProtocolID] = []
    for match in matched where !candidates.contains(match.protocolID) {
      candidates.append(match.protocolID)
    }
    // Different families conflict. Variants of one family resolve to the variant of the lowest
    // interface number, since interfaces are matched in that order.
    guard candidates.count == 1 else {
      return .conflict(.ambiguousProtocolMatch, candidates: candidates)
    }
    // These are raw-USB variants; HID access cannot drive them and must not reach
    // `HIDDescriptor`.
    guard backend.usesRawUSB else {
      return .unsupported(
        .unsupportedTransportVariant,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: signature.protocolID,
          reason: .unsupportedTransportVariant
        )
      )
    }
    guard
      let interface = interfaces.first(where: {
        signature.matches($0)
          && (signature.requiredInterfaceNumber == nil
            || $0.interfaceNumber == signature.requiredInterfaceNumber)
          // Registry-only facts carry no endpoints; claimed-interface validation checks them.
          && ($0.endpoints == nil || hasInterruptPair($0))
      })
    else {
      return .unsupported(
        .interfaceContractMismatch,
        rejected: ProtocolBindingResult.RejectedCandidate(
          protocolID: signature.protocolID,
          reason: .interfaceContractMismatch
        )
      )
    }
    return .bound(
      ProtocolBinding(
        protocolID: signature.protocolID,
        variant: signature.variant,
        accessBackend: backend,
        interfaceNumber: interface.interfaceNumber,
        rule: .interfaceSignature,
        matchedPredicates: interface.endpoints == nil
          ? [.interfaceSignature] : [.interfaceSignature, .interruptEndpointPair],
        record: nil
      )
    )
  }

  static func hasInterruptPair(_ interface: PhysicalInterfaceSignature) -> Bool {
    let endpoints = interface.endpoints ?? []
    return [USBEndpointDirection.in, .out].allSatisfy { direction in
      endpoints.contains {
        $0.address != nil && $0.transferType == .interrupt && $0.direction == direction
      }
    }
  }
}
