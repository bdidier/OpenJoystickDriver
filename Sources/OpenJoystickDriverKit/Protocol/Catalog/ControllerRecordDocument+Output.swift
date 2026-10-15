extension ControllerRecordDocument {
  /// The output section: a rumble template, startup writes, or both. A write with a `report` is
  /// a HID write; one without is a raw-USB write.
  struct Output: Decodable {
    let rumble: RumbleOutputTemplate?
    let startup: [RecordStartupWrite]
    let usbStartup: [USBStartupWrite]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["rumble", "startup"])
      rumble = try container.decodeOptional(RumbleTemplate.self, for: "rumble")?.template
      let startup = try container.decodeOptional([StartupWrite].self, for: "startup")
      self.startup = startup?.compactMap(\.hid) ?? []
      usbStartup = startup?.compactMap(\.usb) ?? []
      guard rumble != nil || startup != nil, startup.map({ (1...16).contains($0.count) }) ?? true
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "output names a rumble template or 1...16 startup writes"
          )
        )
      }
      guard self.startup.isEmpty || usbStartup.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "startup writes are all HID reports or all raw-USB packets"
          )
        )
      }
    }
  }

  /// One startup write of either format.
  struct StartupWrite: Decodable {
    let hid: RecordStartupWrite?
    let usb: USBStartupWrite?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let condition = try StartupWriteCondition.decode(from: container, decoder: decoder)
      do {
        if container.contains(DocumentKey("report")) {
          try container.rejectUnknown(allowed: [
            "report", "bytes", "delayMilliseconds", "transport", "phase", "crc32Seed", "variants",
            "when",
          ])
          hid = try Self.hidWrite(container, condition: condition)
          usb = nil
        } else {
          try container.rejectUnknown(allowed: [
            "bytes", "endpoint", "timeoutMilliseconds", "delayMilliseconds", "sessionByte",
            "toleratesRejection", "variants", "when",
          ])
          usb = try Self.usbWrite(container, condition: condition)
          hid = nil
        }
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: problem.description)
        )
      }
    }

    private static func bytes(
      _ container: KeyedDecodingContainer<DocumentKey>
    ) throws -> [UInt8] {
      let values = try container.decode([Int].self, for: "bytes")
      let bytes = values.compactMap(UInt8.init(exactly:))
      guard bytes.count == values.count else {
        throw ControllerRecordProblem("startup bytes are 0...255")
      }
      return bytes
    }

    private static func hidWrite(
      _ container: KeyedDecodingContainer<DocumentKey>,
      condition: StartupWriteCondition
    ) throws -> RecordStartupWrite {
      let report = try container.decode(TemplateReport.self, for: "report").report
      let transportName = try container.decodeOptional(String.self, for: "transport")
      let transport = transportName.flatMap(PhysicalTransport.init(rawValue:))
        .flatMap { $0 == .proprietaryRadioReceiver ? nil : $0 }
      guard transportName == nil || transport != nil else {
        throw ControllerRecordProblem(
          "a startup transport is usb, bluetooth-classic or bluetooth-le"
        )
      }
      let phaseName = try container.decodeOptional(String.self, for: "phase")
      let phase = phaseName.flatMap(StartupPhase.init(rawValue:))
      guard phaseName == nil || phase != nil else {
        throw ControllerRecordProblem("a startup phase is startup or activation")
      }
      let seed = try container.decodeOptional(Int.self, for: "crc32Seed")
      guard seed.map({ (0...255).contains($0) }) ?? true else {
        throw ControllerRecordProblem("a startup crc32Seed is 0...255")
      }
      return try RecordStartupWrite(
        report: report,
        bytes: bytes(container),
        delayMilliseconds: container.decodeOptional(Int.self, for: "delayMilliseconds"),
        transport: transport,
        phase: phase ?? .activation,
        crc32Seed: seed.map { UInt8($0) },
        condition: condition
      )
    }

    private static func usbWrite(
      _ container: KeyedDecodingContainer<DocumentKey>,
      condition: StartupWriteCondition
    ) throws -> USBStartupWrite {
      let endpoint = try container.decodeOptional(Int.self, for: "endpoint")
      guard endpoint.map(USBStartupWrite.endpointRange.contains) ?? true else {
        throw ControllerRecordProblem("a USB startup endpoint is 1...127")
      }
      return try USBStartupWrite(
        bytes: bytes(container),
        endpoint: endpoint.map { UInt8($0) },
        timeoutMilliseconds: container.decodeOptional(Int.self, for: "timeoutMilliseconds"),
        delayMilliseconds: container.decodeOptional(Int.self, for: "delayMilliseconds"),
        sessionByte: container.decodeOptional(Int.self, for: "sessionByte"),
        toleratesRejection: container.decodeOptional(Bool.self, for: "toleratesRejection")
          ?? false,
        condition: condition
      )
    }
  }
}
