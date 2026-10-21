import Foundation

/// The HID report layout a persona publishes.
enum VirtualDeviceLayout: String, Sendable {
  case ojdGenericGamepad = "OJDGenericGamepad"
  case xboxOneSBluetooth = "XboxOneSBluetooth"
}

/// One `VirtualDevice` document (`virtual-device.schema.json`): either the definition of a
/// persona, or, with `match`, the selection of a persona for one controller model or unit.
struct VirtualDevice: Equatable, Sendable {
  /// The identity a document sets over the persona's.
  struct Identity: Equatable, Sendable {
    let vendorID: UInt16
    let productID: UInt16
    let versionNumber: Int?
    let productName: String
    let manufacturer: String
  }

  /// The `kind` of a virtual device document.
  static let kind = "VirtualDevice"

  let persona: VirtualHIDProfileID
  /// The controller model or unit this document selects the persona for; nil for a definition.
  let match: VirtualHIDProfileOverrideStore.Model?
  let layout: VirtualDeviceLayout?
  let transport: String?
  let labels: VirtualIdentityGlyphFamily?
  /// Whether SDL recognizes the published device with its default hints; nil for a selection.
  let worksWithDefaultSDLHints: Bool?
  let identity: Identity?

  /// The bundled definitions, by persona.
  static let bundled: [VirtualHIDProfileID: Self] = {
    do { return try loadBundled() } catch {
      fatalError("[VirtualDevice] Invalid bundled virtual devices: \(error)")
    }
  }()

  /// The bundled definition of `persona`.
  static func definition(of persona: VirtualHIDProfileID) -> Self {
    guard let device = bundled[persona] else {
      fatalError("[VirtualDevice] No bundled virtual device for \(persona.rawValue)")
    }
    return device
  }

  private static func loadBundled() throws -> [VirtualHIDProfileID: Self] {
    var devices: [VirtualHIDProfileID: Self] = [:]
    for persona in VirtualHIDProfileID.allCases {
      guard let url = Bundle.module.url(forResource: persona.bundledFileName, withExtension: "json")
      else { throw ControllerRecordProblem("no record for \(persona.rawValue)") }
      let device = try decode(Data(contentsOf: url), fileName: url.lastPathComponent)
      guard device.match == nil, device.persona == persona else {
        throw ControllerRecordProblem("\(url.lastPathComponent) must define \(persona.rawValue)")
      }
      devices[persona] = device
    }
    return devices
  }

  /// The identity this definition publishes.
  var profile: VirtualDeviceProfile? {
    guard let identity, let transport, let labels else { return nil }
    return VirtualDeviceProfile(
      vendorID: identity.vendorID,
      productID: identity.productID,
      versionNumber: identity.versionNumber ?? 0,
      productName: identity.productName,
      manufacturer: identity.manufacturer,
      transport: transport,
      glyphFamily: labels
    )
  }
}

extension VirtualHIDProfileID {
  /// The name of the bundled record file, without extension.
  var bundledFileName: String {
    switch self {
    case .generic: "virtual-device.generic"
    case .sdlCompatible: "virtual-device.sdl-compatible"
    }
  }
}
