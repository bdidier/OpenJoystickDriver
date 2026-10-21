extension ControllerRecord {
  /// Whether the signed USB extension can claim this raw-USB controller; nil for a family that
  /// does not use raw USB. The extension's USB entitlement is a product list Apple signs, so a
  /// user record cannot add a product to it.
  public var isClaimedByUSBExtension: Bool? {
    guard usesRawUSB else { return nil }
    return PlatformHosts.current.extensionEntitlementCovers(
      vendorID: model.vendorID,
      productID: model.productID
    )
  }
}
