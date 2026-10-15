extension NamedPacketPlan: Decodable {
  init(from decoder: any Decoder) throws {
    let packets = try decoder.singleValueContainer().decode([NamedPacket].self)
    do {
      try self.init(packets: packets)
    } catch {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: error.description)
      )
    }
  }
}

extension NamedPacket: Decodable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["id", "bytes", "sessionByte"])
    do {
      try self.init(
        id: container.decode(String.self, for: "id"),
        bytes: container.decode([UInt8].self, for: "bytes"),
        sessionByte: container.decode(Int.self, for: "sessionByte")
      )
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: problem.description)
      )
    }
  }
}
