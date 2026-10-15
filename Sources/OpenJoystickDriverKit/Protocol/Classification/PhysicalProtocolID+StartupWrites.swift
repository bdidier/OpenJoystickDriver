extension PhysicalProtocolID {
  /// The raw-USB startup packets a controller of this family receives: the record's own packets
  /// when it names any, otherwise the ones this family's description carries for `variant` and
  /// `parameters`.
  func usbStartupWrites(
    recordWrites: [USBStartupWrite],
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> [USBStartupWrite] {
    guard recordWrites.isEmpty else { return recordWrites }
    return protocolDescription.usbStartupWrites(variant: variant, parameters: parameters)
  }

  /// The fixed keep-alive writes this family's description carries for `variant`.
  func keepAliveWrites(variant: PhysicalProtocolVariantID?) -> [KeepAliveWrite] {
    protocolDescription.keepAliveWrites(variant: variant)
  }

  /// The OUT endpoint a startup packet that names none goes to.
  var descriptionOutputEndpoint: UInt8 { UInt8(protocolDescription.endpoints.output) }
}
