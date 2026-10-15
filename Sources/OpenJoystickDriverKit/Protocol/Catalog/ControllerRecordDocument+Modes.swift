import Foundation

extension ControllerRecordDocument {
  /// One entry of the record's `modes`: an ID, the protocol that mode runs, and, for every mode
  /// but `default`, the match keys that select it.
  struct ModeDocument: Decodable {
    static let defaultID = "default"

    let id: String
    let protocolInfo: ProtocolInfo
    /// Nil exactly for the `default` mode.
    let match: ControllerModeMatch?
    let interfaceRange: ClosedRange<UInt8>?
    /// The session's HID startup writes; nil leaves the record's `output.startup` in force.
    let startupWrites: [RecordStartupWrite]?
    /// The session's raw-USB startup packets; nil leaves the record's `output.usbStartup` in force.
    let usbStartupWrites: [USBStartupWrite]?

    var isDefault: Bool { id == Self.defaultID }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["id", "protocol", "match", "interface", "session"])
      let id = try container.decode(String.self, for: "id")
      guard Self.isValidID(id) else {
        throw Self.invalid("id", "a mode id is lowercase words joined by hyphens", decoder)
      }
      let match = try container.decodeOptional(ModeMatchDocument.self, for: "match")?.match
      let isDefault = id == Self.defaultID
      if isDefault, match != nil {
        throw Self.invalid(
          "match",
          "the default mode has no match; it runs when no other mode does",
          decoder
        )
      }
      if !isDefault, match == nil {
        throw Self.invalid("match", "every mode but default needs a match", decoder)
      }
      self.id = id
      self.match = match
      protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
      interfaceRange = try container.decodeOptional(ModeInterfaceDocument.self, for: "interface")?
        .range
      let session = try container.decodeOptional(ModeSessionDocument.self, for: "session")
      startupWrites = session?.startup
      usbStartupWrites = session?.usbStartup
    }

    static func invalid(
      _ key: String,
      _ message: String,
      _ decoder: any Decoder
    ) -> DecodingError {
      .dataCorrupted(
        .init(codingPath: decoder.codingPath + [DocumentKey(key)], debugDescription: message)
      )
    }

    /// Lowercase ASCII words joined by single hyphens, the first starting with a letter.
    private static func isValidID(_ id: String) -> Bool {
      let words = id.split(separator: "-", omittingEmptySubsequences: false)
      return id.first?.isLetter == true
        && words.allSatisfy { word in
          !word.isEmpty
            && word.unicodeScalars.allSatisfy {
              ("a"..."z").contains($0) || ("0"..."9").contains($0)
            }
        }
    }

    /// The runtime form of this mode.
    var mode: ControllerMode {
      ControllerMode(
        id: id,
        physicalProtocolID: protocolInfo.protocolID,
        physicalProtocolVariant: protocolInfo.protocolVariant,
        parameters: protocolInfo.parameters,
        gipStartupPackets: protocolInfo.initialization ?? [],
        gipKeepAlivePolicy: protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled }
          ?? .enabled,
        assemblyPolicy: protocolInfo.assembly,
        match: match ?? ControllerModeMatch(),
        interfaceRange: interfaceRange,
        startupWrites: startupWrites,
        usbStartupWrites: usbStartupWrites
      )
    }
  }

  /// A mode's `interface`: an inclusive range of interface numbers.
  struct ModeInterfaceDocument: Decodable {
    let range: ClosedRange<UInt8>

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["first", "last"])
      let first = try container.decode(Int.self, for: "first")
      let last = try container.decode(Int.self, for: "last")
      guard let low = UInt8(exactly: first), let high = UInt8(exactly: last), low <= high else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "an interface range is 0...255 with first not above last"
          )
        )
      }
      range = low...high
    }
  }

  /// A mode's `session`: the steps it runs in place of the record's own. A HID mode names
  /// `startup` (HID reports); a raw-USB mode names `usbStartup` (USB packets).
  struct ModeSessionDocument: Decodable {
    let startup: [RecordStartupWrite]?
    let usbStartup: [USBStartupWrite]?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["startup", "usbStartup"])
      guard
        container.contains(DocumentKey("startup")) != container.contains(DocumentKey("usbStartup"))
      else {
        throw ModeDocument.invalid(
          "startup",
          "a session names exactly one of startup (HID reports) and usbStartup (USB packets)",
          decoder
        )
      }
      let key = container.contains(DocumentKey("startup")) ? "startup" : "usbStartup"
      let writes = try container.decode([StartupWrite].self, for: key)
      guard (1...16).contains(writes.count) else {
        throw ModeDocument.invalid(key, "a session names 1...16 startup writes", decoder)
      }
      if key == "startup" {
        guard writes.allSatisfy({ $0.hid != nil }) else {
          throw ModeDocument.invalid(key, "startup names HID reports, not USB packets", decoder)
        }
        startup = writes.compactMap(\.hid)
        usbStartup = nil
      } else {
        guard writes.allSatisfy({ $0.usb != nil }) else {
          throw ModeDocument.invalid(key, "usbStartup names USB packets, not HID reports", decoder)
        }
        startup = nil
        usbStartup = writes.compactMap(\.usb)
      }
    }
  }

  /// A mode's match keys; every key present must hold.
  struct ModeMatchDocument: Decodable {
    let match: ControllerModeMatch

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(
        allowed: ["link", "interfaceSignature", "manufacturer", "product", "bcdDevice", "probes"]
      )
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "a match needs at least one key")
        )
      }
      var match = ControllerModeMatch()
      if let name = try container.decodeOptional(String.self, for: "link") {
        guard let link = PhysicalTransport(rawValue: name) else {
          throw ModeDocument.invalid(
            "link",
            "link is usb, bluetooth-classic, bluetooth-le or proprietary-radio-receiver",
            decoder
          )
        }
        match.link = link
      }
      match.interfaceSignature =
        try container.decodeOptional(
          ModeInterfaceSignatureDocument.self,
          for: "interfaceSignature"
        )?
        .signature
      match.manufacturer = try Self.text("manufacturer", container, decoder)
      match.product = try Self.text("product", container, decoder)
      match.bcdDevice = try container.decodeOptional(BCDRangeDocument.self, for: "bcdDevice")?.range
      if let entries = try container.decodeOptional([ModeProbeDocument].self, for: "probes") {
        guard !entries.isEmpty else {
          throw ModeDocument.invalid("probes", "a mode needs at least one probe", decoder)
        }
        match.probes = entries.map(\.probe)
      }
      self.match = match
    }

    private static func text(
      _ key: String,
      _ container: KeyedDecodingContainer<DocumentKey>,
      _ decoder: any Decoder
    ) throws -> String? {
      guard let text = try container.decodeOptional(String.self, for: key) else { return nil }
      guard !text.isEmpty else {
        throw ModeDocument.invalid(key, "\(key) must not be empty", decoder)
      }
      return text
    }
  }

  /// An interface the device must expose: its USB class triple and, optionally, its HID usage.
  struct ModeInterfaceSignatureDocument: Decodable {
    let signature: ControllerModeMatch.InterfaceSignature

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(
        allowed: [
          "interfaceClass", "interfaceSubclass", "interfaceProtocol", "usagePage", "usage",
          "endpoints",
        ]
      )
      func byte(_ key: String) throws -> UInt8 {
        guard let byte = UInt8(exactly: try container.decode(Int.self, for: key)) else {
          throw ModeDocument.invalid(key, "\(key) is 0...255", decoder)
        }
        return byte
      }
      func word(_ key: String) throws -> UInt32? {
        guard let value = try container.decodeOptional(Int.self, for: key) else { return nil }
        guard (0...65_535).contains(value) else {
          throw ModeDocument.invalid(key, "\(key) is 0...65535", decoder)
        }
        return UInt32(value)
      }
      let usagePage = try word("usagePage")
      let usage = try word("usage")
      guard usage == nil || usagePage != nil else {
        throw ModeDocument.invalid("usage", "usage needs usagePage", decoder)
      }
      signature = ControllerModeMatch.InterfaceSignature(
        interfaceClass: try byte("interfaceClass"),
        interfaceSubclass: try byte("interfaceSubclass"),
        interfaceProtocol: try byte("interfaceProtocol"),
        usagePage: usagePage,
        usage: usage,
        endpoints: try container.decodeOptional([ModeEndpointDocument].self, for: "endpoints")?
          .map(\.endpoint)
      )
      if let count = signature.endpoints?.count, count == 0 {
        throw ModeDocument.invalid("endpoints", "endpoints names at least one endpoint", decoder)
      }
    }
  }

  /// One endpoint of an interface signature's endpoint set.
  struct ModeEndpointDocument: Decodable {
    let endpoint: ControllerModeMatch.InterfaceSignature.Endpoint

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "address", "direction", "transferType", "maxPacketSize",
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "an endpoint needs at least one key"
          )
        )
      }
      var endpoint = ControllerModeMatch.InterfaceSignature.Endpoint()
      if let address = try container.decodeOptional(Int.self, for: "address") {
        guard let byte = UInt8(exactly: address) else {
          throw ModeDocument.invalid("address", "address is 0...255", decoder)
        }
        endpoint.address = byte
      }
      if let name = try container.decodeOptional(String.self, for: "direction") {
        guard let direction = USBEndpointDirection(rawValue: name) else {
          throw ModeDocument.invalid("direction", "direction is in or out", decoder)
        }
        endpoint.direction = direction
      }
      if let name = try container.decodeOptional(String.self, for: "transferType") {
        guard let type = USBEndpointTransferType(rawValue: name), type != .unknown else {
          throw ModeDocument.invalid(
            "transferType",
            "transferType is control, isochronous, bulk, or interrupt",
            decoder
          )
        }
        endpoint.transferType = type
      }
      if let size = try container.decodeOptional(Int.self, for: "maxPacketSize") {
        guard let word = UInt16(exactly: size) else {
          throw ModeDocument.invalid("maxPacketSize", "maxPacketSize is 0...65535", decoder)
        }
        endpoint.maxPacketSize = word
      }
      self.endpoint = endpoint
    }
  }

  /// An inclusive range of `bcdDevice` values.
  struct BCDRangeDocument: Decodable {
    let range: ClosedRange<UInt16>

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["min", "max"])
      let low = try container.decode(Int.self, for: "min")
      let high = try container.decode(Int.self, for: "max")
      guard let min = UInt16(exactly: low), let max = UInt16(exactly: high), min <= max else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "a bcdDevice range is 0...65535 with min not above max"
          )
        )
      }
      range = min...max
    }
  }

  /// A probe: a read of one feature report, with no way to write.
  struct ModeProbeDocument: Decodable {
    let probe: ControllerModeProbe

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["report", "length", "expect", "offset", "bytes"])
      let report = try container.decode(Int.self, for: "report")
      let length = try container.decode(Int.self, for: "length")
      let expect = try container.decode(String.self, for: "expect")
      let offset = try container.decodeOptional(Int.self, for: "offset")
      let hex = try container.decodeOptional(String.self, for: "bytes")
      guard let reportID = UInt8(exactly: report), (1...65_535).contains(length) else {
        throw Self.invalid("a probe reads report 0...255 with a length of 1...65535", decoder)
      }
      let expectation: ControllerModeProbe.Expectation
      switch (expect, offset, hex) {
      case ("answers", nil, nil): expectation = .answers
      case ("stalls", nil, nil): expectation = .stalls
      case ("bytes", let offset?, let hex?):
        guard let expected = Self.bytes(hex), offset >= 0, offset + expected.count <= length else {
          throw Self.invalid(
            "probe bytes are uppercase hex pairs that fit the read length",
            decoder
          )
        }
        expectation = .bytes(offset: offset, expected: expected)
      default:
        throw Self.invalid(
          "a probe expects answers, stalls, or bytes; only bytes carries offset and bytes",
          decoder
        )
      }
      probe = ControllerModeProbe(reportID: reportID, length: length, expectation: expectation)
    }

    private static func invalid(_ message: String, _ decoder: any Decoder) -> DecodingError {
      .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
    }

    /// Uppercase hex pairs separated by single spaces; nil for anything else.
    private static func bytes(_ text: String) -> [UInt8]? {
      let pairs = text.split(separator: " ", omittingEmptySubsequences: false)
      let digits = Set("0123456789ABCDEF")
      let values = pairs.compactMap { pair -> UInt8? in
        pair.count == 2 && pair.allSatisfy(digits.contains) ? UInt8(pair, radix: 16) : nil
      }
      return values.count == pairs.count ? values : nil
    }
  }

  /// The record's modes: unique IDs and exactly one `default`; every mode's protocol obeys the
  /// same record-level rules the default protocol does, whether the record has one mode or many.
  /// A session names HID reports for a HID mode and USB packets for a raw-USB mode, and
  /// `interface` selects among HID interfaces, so a raw-USB mode has none.
  func validateModes(codingPath: [any CodingKey]) throws {
    let path = codingPath + [DocumentKey("modes")]
    func fail(_ message: String) -> DecodingError {
      .dataCorrupted(.init(codingPath: path, debugDescription: message))
    }
    guard !modes.isEmpty else { throw fail("modes must not be empty") }
    guard modes.filter(\.isDefault).count == 1 else {
      throw fail("modes need exactly one mode with the id default")
    }
    guard Set(modes.map(\.id)).count == modes.count else { throw fail("mode IDs must be unique") }
    for mode in modes {
      let info = mode.protocolInfo
      let rawUSB = info.protocolID.usesRawUSB(storedVariant: info.protocolVariant)
      if rawUSB {
        if mode.interfaceRange != nil {
          throw fail(
            "interface selects among HID interfaces; a raw-USB mode claims the interface its"
              + " usb transport resolves"
          )
        }
        if mode.startupWrites != nil {
          throw fail("a raw-USB mode's session names usbStartup packets, not HID reports")
        }
        if !startupWrites.isEmpty {
          throw fail("HID startup writes apply only to HID controllers, so not to a raw-USB mode")
        }
        let carriesUSBWrites =
          ProtocolDescription.bundled[info.protocolID]?.usbStartupWrites.isEmpty == false
        if !(mode.usbStartupWrites ?? usbStartupWrites).isEmpty,
          !carriesUSBWrites || info.initialization != nil
        {
          throw fail(
            "raw-USB startup writes need a family that reads them and no initialization list"
          )
        }
      } else if mode.usbStartupWrites != nil {
        throw fail("a HID mode's session names startup reports, not usbStartup packets")
      }
      if (inputLayout != nil) != info.protocolID.requiresRecordInputLayout {
        throw fail(
          "every mode needs the record's input layout exactly when it is hid.report-layout"
        )
      }
      if rumbleTemplate != nil, !info.protocolID.encodesRumbleTemplate {
        throw fail("rumble templates require a driver that encodes them in every mode")
      }
      guard capabilitiesAreDeclared(by: info.protocolID) else {
        throw fail("capabilities must be deltas the driver of every mode declares")
      }
    }
  }
}
