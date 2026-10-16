import Foundation

/// Raw bytes in a document: uppercase hex pairs separated by single spaces.
enum HexBytes {
  static let message = "bytes are uppercase hex pairs separated by single spaces"

  /// The bytes of `text`; nil unless it is one or more uppercase hex pairs separated by single
  /// spaces.
  static func parse(_ text: String) -> [UInt8]? {
    let pairs = text.split(separator: " ", omittingEmptySubsequences: false)
    let digits = Set("0123456789ABCDEF")
    let values = pairs.compactMap { pair -> UInt8? in
      pair.count == 2 && pair.allSatisfy(digits.contains) ? UInt8(pair, radix: 16) : nil
    }
    return values.count == pairs.count ? values : nil
  }

  /// The bytes under `key`, or a problem naming `what`.
  static func decode(
    _ container: KeyedDecodingContainer<DocumentKey>,
    for key: String,
    what: String
  ) throws -> [UInt8] {
    guard let bytes = parse(try container.decode(String.self, for: key)) else {
      throw ControllerRecordProblem("\(what) \(message)")
    }
    return bytes
  }
}

extension ControllerRecordDocument {
  /// A `startup` list: 1...16 writes that are all HID reports, all raw-USB packets or all named
  /// packets of a protocol description.
  struct StartupList: Decodable {
    let hid: [RecordStartupWrite]
    let usb: [USBStartupWrite]
    let packets: [StartupPacketReference]

    init(from decoder: any Decoder) throws {
      let writes = try [StartupWrite](from: decoder)
      guard (1...16).contains(writes.count) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "startup names 1...16 writes")
        )
      }
      hid = writes.compactMap(\.hid)
      usb = writes.compactMap(\.usb)
      packets = writes.compactMap(\.packet)
      guard [hid.isEmpty, usb.isEmpty, packets.isEmpty].filter({ !$0 }).count <= 1 else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "startup writes are all HID reports, all raw-USB packets or all named packets"
          )
        )
      }
    }
  }

  /// A mode's `session`: the one shape every mode uses for its initialization, keep-alive,
  /// settle, shutdown, vendor control transfers and rumble template.
  struct SessionDocument: Decodable {
    let session: ControllerSession

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "startup", "keepAlive", "settleMilliseconds", "shutdown", "control", "rumble",
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "session must not be empty")
        )
      }
      let startup = try container.decodeOptional(StartupList.self, for: "startup")
      let settle = try container.decodeOptional(Int.self, for: "settleMilliseconds")
      guard settle.map(ControllerSession.settleRange.contains) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("settleMilliseconds")],
            debugDescription: "settleMilliseconds must be in 1...60000"
          )
        )
      }
      let shutdown = try container.decodeOptional([StartupWrite].self, for: "shutdown")
      guard shutdown.map({ (1...8).contains($0.count) && $0.allSatisfy { $0.usb != nil } }) ?? true
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("shutdown")],
            debugDescription: "shutdown names 1...8 raw-USB packets"
          )
        )
      }
      let control = try container.decodeOptional([ControlTransferDocument].self, for: "control")
      guard control.map({ (1...16).contains($0.count) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("control")],
            debugDescription: "control names 1...16 vendor control transfers"
          )
        )
      }
      session = ControllerSession(
        startupWrites: startup?.hid ?? [],
        usbStartupWrites: startup?.usb ?? [],
        keepAlive: try container.decodeOptional(RecordKeepAlive.self, for: "keepAlive")?.keepAlive,
        settleMilliseconds: settle,
        shutdownWrites: shutdown?.compactMap(\.usb) ?? [],
        controlTransfers: control?.map(\.transfer) ?? [],
        rumbleTemplate: try container.decodeOptional(RumbleTemplate.self, for: "rumble")?.template
      )
    }
  }

  /// A record's keep-alive: raw-USB packets repeated at an interval.
  struct RecordKeepAlive: Decodable {
    let keepAlive: KeepAlive

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["intervalMilliseconds", "writes"])
      let writes = try container.decode([KeepAlivePacket].self, for: "writes")
      do {
        keepAlive = try KeepAlive(
          intervalMilliseconds: container.decode(Int.self, for: "intervalMilliseconds"),
          writes: writes.map { KeepAliveWrite(payload: .usb($0.write), resendTuning: nil) }
        )
        guard !writes.isEmpty else {
          throw ControllerRecordProblem("keepAlive names no writes or 1...8 of them")
        }
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: problem.description)
        )
      }
    }
  }

  /// One packet of a record's keep-alive.
  struct KeepAlivePacket: Decodable {
    let write: USBStartupWrite

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "bytes", "endpoint", "timeoutMilliseconds", "sessionByte",
      ])
      do {
        write = try StartupWrite.usbWrite(container, condition: .always)
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: problem.description)
        )
      }
    }
  }

  /// One entry of a session's `control`.
  struct ControlTransferDocument: Decodable {
    let transfer: VendorControlTransfer

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "bmRequestType", "bRequest", "wValue", "wIndex", "wLength", "data", "timeoutMilliseconds",
        "delayMilliseconds", "toleratesRejection", "match",
      ])
      func invalid(_ key: String, _ message: String) -> DecodingError {
        .dataCorrupted(
          .init(codingPath: decoder.codingPath + [DocumentKey(key)], debugDescription: message)
        )
      }
      func word(_ key: String, _ limit: Int) throws -> Int {
        let value = try container.decode(Int.self, for: key)
        guard (0...limit).contains(value) else { throw invalid(key, "\(key) is 0...\(limit)") }
        return value
      }
      let requestType = try word("bmRequestType", 255)
      guard VendorControlTransfer.requestTypes.contains(UInt8(requestType)) else {
        throw invalid("bmRequestType", "bmRequestType is a vendor request type")
      }
      let length = try word("wLength", 255)
      guard VendorControlTransfer.lengthRange.contains(length) else {
        throw invalid("wLength", "wLength is 0...64")
      }
      var data: [UInt8]?
      if container.contains(DocumentKey("data")) {
        do {
          data = try HexBytes.decode(container, for: "data", what: "control transfer data")
        } catch let problem as ControllerRecordProblem {
          throw invalid("data", problem.description)
        }
      }
      let isInput = requestType & 0x80 != 0
      guard isInput ? (data == nil && length >= 1) : (data?.count ?? 0) == length else {
        throw invalid(
          "data",
          isInput
            ? "an IN control transfer reads wLength bytes and carries no data"
            : "control transfer data has \(data?.count ?? 0) bytes, but wLength is \(length)"
        )
      }
      let timeout = try container.decodeOptional(Int.self, for: "timeoutMilliseconds")
      guard timeout.map(VendorControlTransfer.timeoutRange.contains) ?? true else {
        throw invalid("timeoutMilliseconds", "a control transfer timeout is 1...60000 ms")
      }
      let delay = try container.decodeOptional(Int.self, for: "delayMilliseconds")
      guard delay.map(VendorControlTransfer.delayRange.contains) ?? true else {
        throw invalid("delayMilliseconds", "a control transfer delay is 0...1000 ms")
      }
      transfer = VendorControlTransfer(
        bmRequestType: UInt8(requestType),
        bRequest: UInt8(try word("bRequest", 255)),
        wValue: UInt16(try word("wValue", 65_535)),
        wIndex: UInt16(try word("wIndex", 65_535)),
        wLength: UInt16(length),
        data: data,
        timeoutMilliseconds: timeout,
        delayMilliseconds: delay,
        toleratesRejection: try container.decodeOptional(Bool.self, for: "toleratesRejection")
          ?? false,
        match: try container.decodeOptional(ControlGateDocument.self, for: "match")?.gate
          ?? VendorControlTransfer.Gate(manufacturer: nil, product: nil, bcdDevice: nil)
      )
    }
  }

  /// A control transfer's `match`: the device strings and release that must hold.
  struct ControlGateDocument: Decodable {
    let gate: VendorControlTransfer.Gate

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["manufacturer", "product", "bcdDevice"])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "a match needs at least one key")
        )
      }
      func text(_ key: String) throws -> String? {
        guard let text = try container.decodeOptional(String.self, for: key) else { return nil }
        guard !text.isEmpty else {
          throw ModeDocument.invalid(key, "\(key) must not be empty", decoder)
        }
        return text
      }
      gate = VendorControlTransfer.Gate(
        manufacturer: try text("manufacturer"),
        product: try text("product"),
        bcdDevice: try container.decodeOptional(BCDRangeDocument.self, for: "bcdDevice")?.range
      )
    }
  }
}
