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
  /// `Double` that has the decimal value of the text, so `1.0` is written `1` and `1e3` `1000`. A
  /// number none of these holds exactly throws: `1e-400` would become 0 and
  /// `1.23456789012345678901` would lose digits as a `Double`.
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
      } else if let double = Double(text), Self.isExact(double, for: text) {
        try container.encode(double)
      } else {
        throw EncodingError.invalidValue(
          text,
          .init(
            codingPath: encoder.codingPath,
            debugDescription: "\(text) is not exactly a finite Double"
          )
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

  /// Whether `double` has exactly the decimal value of the JSON number `text`: it is finite, the
  /// text fits a `Decimal`, and a nonzero text did not round to zero.
  private static func isExact(_ double: Double, for text: String) -> Bool {
    let mantissa = text.prefix { $0 != "e" && $0 != "E" }
    if double == 0 { return !mantissa.contains { "123456789".contains($0) } }
    guard double.isFinite, let written = Decimal(string: text),
      let held = Decimal(string: "\(double)")
    else { return false }
    return written == held
  }
}
