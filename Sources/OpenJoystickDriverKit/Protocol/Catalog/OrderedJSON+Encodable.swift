import Foundation

extension OrderedJSON: Encodable {
  private struct MemberKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  /// Encodes the value for `JSONEncoder`, which orders an object's members itself (`ojd` sorts
  /// them) and writes a number's value, not its text: an integer that fits 64 bits as an
  /// integer, a larger one as a `Decimal` when it holds every digit, and any other number as a
  /// `Double`, so `1.0` is written `1` and `1e3` `1000`. A number none of these holds exactly
  /// throws.
  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .object(let members):
      var container = encoder.container(keyedBy: MemberKey.self)
      for member in members {
        try container.encode(member.value, forKey: MemberKey(stringValue: member.key))
      }
    case .array(let items):
      var container = encoder.unkeyedContainer()
      for item in items { try container.encode(item) }
    case .string(let text):
      var container = encoder.singleValueContainer()
      try container.encode(text)
    case .number(let text):
      var container = encoder.singleValueContainer()
      if !text.contains(where: { ".eE".contains($0) }) {
        if let integer = Int64(text) {
          try container.encode(integer)
        } else if let integer = UInt64(text) {
          try container.encode(integer)
        } else if let decimal = Decimal(string: text), text == "\(decimal)" {
          try container.encode(decimal)
        } else {
          throw EncodingError.invalidValue(
            text,
            .init(codingPath: encoder.codingPath, debugDescription: "\(text) has too many digits")
          )
        }
      } else if let double = Double(text), double.isFinite {
        try container.encode(double)
      } else {
        throw EncodingError.invalidValue(
          text,
          .init(codingPath: encoder.codingPath, debugDescription: "\(text) is not a finite Double")
        )
      }
    case .bool(let flag):
      var container = encoder.singleValueContainer()
      try container.encode(flag)
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    }
  }
}
