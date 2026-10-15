import Foundation

/// Control-glyph and system-symbol family for a published virtual identity.
public enum VirtualIdentityGlyphFamily: String, Codable, CaseIterable, Sendable {
  case xbox
  case generic
}

/// SF Symbol and glyph family owned by the published USB product, not the physical pad.
public struct VirtualIdentityPresentation: Equatable, Hashable, Sendable {
  public let glyphFamily: VirtualIdentityGlyphFamily
  public let controllerSymbolName: String
  public let controllerSymbolFallback: String

  public init(
    glyphFamily: VirtualIdentityGlyphFamily,
    controllerSymbolName: String,
    controllerSymbolFallback: String = "gamecontroller"
  ) {
    self.glyphFamily = glyphFamily
    self.controllerSymbolName = controllerSymbolName
    self.controllerSymbolFallback = controllerSymbolFallback
  }

  public static let xbox = Self(glyphFamily: .xbox, controllerSymbolName: "xbox.logo")
  public static let generic = Self(glyphFamily: .generic, controllerSymbolName: "gamecontroller")

  public static let playstation = Self(
    glyphFamily: .generic,
    controllerSymbolName: "logo.playstation"
  )

  public static func forProfile(_ profile: VirtualDeviceProfile) -> Self {
    switch profile.glyphFamily {
    case .xbox: .xbox
    case .generic: .generic
    }
  }
}

extension VirtualDeviceProfile {
  public var presentation: VirtualIdentityPresentation {
    VirtualIdentityPresentation.forProfile(self)
  }

  /// Official USB product string plus published VID/PID, not the physical pad name.
  public var publishedUSBIdentityLabel: String {
    "\(productName) (\(String(format: "%04X:%04X", vendorID, productID)))"
  }
}

extension PhysicalProtocolID {
  /// Glyph presentation of the physical controller family, for a controller that publishes no
  /// virtual device.
  public var physicalPresentation: VirtualIdentityPresentation {
    switch self {
    case .xboxXID, .xboxXUSB, .xboxGIP: .xbox
    case .sonySixaxis, .sonyDualShock4, .sonyDualSense, .vendorPS3ThirdParty: .playstation
    case .hidDescriptor, .hidReportLayout, .nintendoSwitch1, .nintendoSwitch2,
      .nintendoSwitchInputOnly, .valveSteamController, .valveSteamTriton, .valveSteamDeck,
      .vendorFlydigi, .vendorGameSir, .vendorNVIDIAShield:
      .generic
    }
  }
}
