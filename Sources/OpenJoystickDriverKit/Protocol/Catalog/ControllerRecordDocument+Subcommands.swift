extension SubcommandPlan: Decodable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["reportId", "counterModulus", "requests"])
    do {
      try self.init(
        reportID: container.decode(UInt8.self, for: "reportId"),
        counterModulus: container.decode(Int.self, for: "counterModulus"),
        requests: container.decode([SubcommandRequest].self, for: "requests")
      )
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: problem.description)
      )
    }
  }
}

extension SubcommandRequest: Decodable {
  /// A request with an `spiRead` is an SPI read; one without carries its `data`.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["subcommand", "data", "spiRead"])
    let subcommand = try container.decode(UInt8.self, for: "subcommand")
    var data: [UInt8]?
    if container.contains(DocumentKey("data")) {
      do {
        data = try HexBytes.decode(container, for: "data", what: "subcommand request data")
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("data")],
            debugDescription: problem.description
          )
        )
      }
    }
    let read = try container.decodeOptional(SPIRead.self, for: "spiRead")
    do {
      switch (data, read) {
      case (let data?, nil): try self.init(subcommand: subcommand, data: data)
      case (nil, let read?): try self.init(subcommand: subcommand, spiRead: read)
      default:
        throw ControllerRecordProblem("a subcommand request names exactly one of data and spiRead")
      }
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: problem.description)
      )
    }
  }
}

extension SubcommandRequest.SPIRead: Decodable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["address", "length", "purpose"])
    let name = try container.decode(String.self, for: "purpose")
    let length = try container.decode(Int.self, for: "length")
    guard let purpose = Purpose(rawValue: name), Self.lengthRange.contains(length) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "an SPI read has a known purpose and a length of 1...29"
        )
      )
    }
    self.init(
      address: try container.decode(UInt32.self, for: "address"),
      length: UInt8(length),
      purpose: purpose
    )
  }
}
