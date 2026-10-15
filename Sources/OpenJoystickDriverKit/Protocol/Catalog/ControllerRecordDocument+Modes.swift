import Foundation

extension ControllerRecordDocument {
  /// One entry of the record's `modes`: an ID, the protocol that mode runs, and the probes that
  /// select it.
  struct ModeDocument: Decodable {
    let id: String
    let protocolInfo: ProtocolInfo
    let probes: [ControllerModeProbe]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["id", "protocol", "match"])
      id = try container.decode(String.self, for: "id")
      guard Self.isValidID(id) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("id")],
            debugDescription: "a mode id is lowercase words joined by hyphens and is not default"
          )
        )
      }
      protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
      probes = try container.decode(ModeMatch.self, for: "match").probes
    }

    /// Lowercase ASCII words joined by single hyphens, the first starting with a letter; the ID
    /// `default` names the record's own protocol.
    private static func isValidID(_ id: String) -> Bool {
      let words = id.split(separator: "-", omittingEmptySubsequences: false)
      return id != "default" && id.first?.isLetter == true
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
        gipStartupPackets: protocolInfo.initialization ?? GIPStartupPacket.defaultSequence,
        gipKeepAlivePolicy: protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled }
          ?? .enabled,
        assemblyPolicy: protocolInfo.assembly,
        probes: probes
      )
    }
  }

  /// A mode's match keys. Probes are the only key.
  struct ModeMatch: Decodable {
    let probes: [ControllerModeProbe]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["probes"])
      let entries = try container.decode([ModeProbeDocument].self, for: "probes")
      guard !entries.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("probes")],
            debugDescription: "a mode needs at least one probe"
          )
        )
      }
      probes = entries.map(\.probe)
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

  /// Modes are alternatives of an HID controller's protocol: unique IDs, and each mode's protocol
  /// obeys the same record-level rules the default protocol does.
  func validateModes(codingPath: [any CodingKey]) throws {
    guard !modes.isEmpty else { return }
    let path = codingPath + [DocumentKey("modes")]
    func fail(_ message: String) -> DecodingError {
      .dataCorrupted(.init(codingPath: path, debugDescription: message))
    }
    guard Set(modes.map(\.id)).count == modes.count else { throw fail("mode IDs must be unique") }
    let protocols = [protocolInfo] + modes.map(\.protocolInfo)
    for info in protocols {
      if info.protocolID.usesRawUSB(storedVariant: info.protocolVariant) {
        throw fail("modes apply only to HID controllers")
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
