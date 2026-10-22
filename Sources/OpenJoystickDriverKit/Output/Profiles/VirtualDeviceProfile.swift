/// Stable identity constants for OpenJoystickDriver-created virtual HID devices.
///
/// These values are used to:
/// - disambiguate our virtual devices from real controllers with the same VID/PID
/// - avoid ambiguous `LocationID=0/1` heuristics in some HID consumers
public enum VirtualDeviceIdentityConstants {
  /// User-space IOHIDUserDevice LocationID namespace.
  ///
  /// We intentionally use a *range* (not a single constant) so we can create one
  /// virtual controller per physical controller without collisions.
  ///
  /// The high 16 bits ("OJ") are a stable namespace. The low 16 bits are derived
  /// (deterministically) from the physical device identifier.
  public static let userSpaceLocationIDNamespace: UInt32 = 0x4F4A_0000  // "OJ" namespace
}
/// Defines the virtual HID device identity presented to the OS.
///
/// Physical input is normalized to the internal virtual-gamepad state; the
/// profile controls the selected HID descriptor and consumer identity.
public struct VirtualDeviceProfile: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  /// Value used for `kIOHIDVersionNumberKey` / SDL "product version".
  ///
  /// SDL includes this 16-bit value in the GUID it uses to look up controller mappings.
  /// For some SDL-based consumers on macOS, having the expected version is required for
  /// automatic mapping to be applied.
  public let versionNumber: Int
  public let productName: String
  public let manufacturer: String
  public let transport: String
  /// The control glyphs and system symbol the published product shows.
  public let glyphFamily: VirtualIdentityGlyphFamily

  /// The `Generic` persona's identity: a stable non-spoof Generic HID identity. Its name,
  /// version, descriptor, and report layout form one consumer contract; incompatible layouts
  /// require a new product ID. The values come from the bundled `VirtualDevice` record.
  public static var generic: Self { VirtualHIDProfileID.generic.identity }

  /// The `SDLCompatible` persona's identity, an Xbox One S identity whose reports are Xbox One
  /// GIP packets. This is not XInputHID or XUSB emulation. The values come from the bundled
  /// `VirtualDevice` record.
  public static var sdlCompatible: Self { VirtualHIDProfileID.sdlCompatible.identity }

  /// This profile with the identity of a persona over it. The transport and, unless the persona
  /// sets one, the version number stay those of the built-in profile, so the report descriptor
  /// and the report layout keep their contract.
  public func applying(_ identity: VirtualPersona.Identity) -> Self {
    Self(
      vendorID: identity.vendorID,
      productID: identity.productID,
      versionNumber: identity.versionNumber ?? versionNumber,
      productName: identity.productName,
      manufacturer: identity.manufacturer,
      transport: transport,
      glyphFamily: identity.glyphFamily
    )
  }
}
