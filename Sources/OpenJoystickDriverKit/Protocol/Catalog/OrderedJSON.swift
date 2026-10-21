import Foundation

/// A JSON value that keeps the order of an object's members, and the text format of the
/// controller record files: two-space indent, `"key": value`, every object expanded, and an
/// array on one line when the line stays within 80 columns.
///
/// Every record text the app shows or writes comes from ``formatted()``, so it reads like the
/// bundled `Resources/Controllers` files, which `biome` formats the same way.
public indirect enum OrderedJSON: Equatable, Sendable {
  case object([Member])
  case array([Self])
  case string(String)
  /// A number as JSON text, such as `-1.5e3`.
  case number(String)
  case bool(Bool)
  case null

  public struct Member: Equatable, Sendable {
    public let key: String
    public let value: OrderedJSON

    public init(key: String, value: OrderedJSON) {
      self.key = key
      self.value = value
    }
  }

  /// A JSON text that does not parse, or a value JSON cannot hold.
  public struct Problem: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
  }

  /// The widest line the array layout keeps on one line.
  static let lineWidth = 80
  static let indentWidth = 2

  // MARK: Foundation values

  /// `value`, a `JSONSerialization` object, with each object's members in the order of `order`
  /// and the members `order` lacks after them in sorted order. Array items take the order of the
  /// item at the same position.
  public init(foundation value: Any, order: Self? = nil) throws {
    switch value {
    case let dictionary as [String: Any]:
      var guide: [String: Self] = [:]
      var guided: [String] = []
      if case .object(let members)? = order {
        guided = members.map(\.key)
        for member in members { guide[member.key] = member.value }
      }
      let guidedKeys = Set(guided)
      let keys =
        guided.filter { dictionary[$0] != nil }
        + dictionary.keys.filter { !guidedKeys.contains($0) }.sorted()
      var members: [Member] = []
      for key in keys {
        guard let child = dictionary[key] else { preconditionFailure("key from the dictionary") }
        members.append(Member(key: key, value: try Self(foundation: child, order: guide[key])))
      }
      self = .object(members)
    case let list as [Any]:
      var guideItems: [Self] = []
      if case .array(let items)? = order { guideItems = items }
      var items: [Self] = []
      for (index, item) in list.enumerated() {
        items.append(
          try Self(foundation: item, order: index < guideItems.count ? guideItems[index] : nil)
        )
      }
      self = .array(items)
    case let text as String:
      self = .string(text)
    case is NSNull:
      self = .null
    // swiftlint:disable:next legacy_objc_type
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        self = .bool(number.boolValue)
      } else if CFNumberIsFloatType(number) {
        guard number.doubleValue.isFinite else {
          throw Problem(description: "JSON cannot hold a number that is not finite")
        }
        self = .number("\(number.doubleValue)")
      } else {
        self = .number(number.stringValue)
      }
    default:
      throw Problem(description: "\(type(of: value)) is not a JSON value")
    }
  }

  // MARK: Parsing

  /// The value in `data`, a UTF-8 JSON document.
  public static func parse(_ data: Data) throws -> Self {
    var parser = Parser(bytes: [UInt8](data))
    parser.skipSpace()
    let value = try parser.value()
    parser.skipSpace()
    guard parser.atEnd else { throw parser.problem("unexpected text after the value") }
    return value
  }

  // MARK: Formatting

  /// The record file text, ending in a newline.
  public func formatted() -> String {
    var output = ""
    write(into: &output, indent: 0, prefix: 0, suffix: 0)
    output += "\n"
    return output
  }

  /// ``formatted()`` as UTF-8.
  public func formattedData() -> Data { Data(formatted().utf8) }

  /// Writes the value. `prefix` is the columns already used on the line before the value (the
  /// indent and the key), `suffix` the columns a trailing comma needs.
  private func write(into output: inout String, indent: Int, prefix: Int, suffix: Int) {
    switch self {
    case .object(let members):
      guard !members.isEmpty else {
        output += "{}"
        return
      }
      output += "{\n"
      let inner = indent + Self.indentWidth
      for (index, member) in members.enumerated() {
        let key = Self.quoted(member.key) + ": "
        let last = index == members.count - 1
        output += String(repeating: " ", count: inner) + key
        member.value.write(
          into: &output,
          indent: inner,
          prefix: inner + key.count,
          suffix: last ? 0 : 1
        )
        output += last ? "\n" : ",\n"
      }
      output += String(repeating: " ", count: indent) + "}"
    case .array(let items):
      guard !items.isEmpty else {
        output += "[]"
        return
      }
      if let flat = flatText, prefix + flat.count + suffix <= Self.lineWidth {
        output += flat
        return
      }
      output += "[\n"
      let inner = indent + Self.indentWidth
      for (index, item) in items.enumerated() {
        let last = index == items.count - 1
        output += String(repeating: " ", count: inner)
        item.write(into: &output, indent: inner, prefix: inner, suffix: last ? 0 : 1)
        output += last ? "\n" : ",\n"
      }
      output += String(repeating: " ", count: indent) + "]"
    default:
      output += flatText ?? ""
    }
  }

  /// The one-line text of a value with no filled object in it; nil otherwise.
  private var flatText: String? {
    switch self {
    case .object(let members): return members.isEmpty ? "{}" : nil
    case .array(let items):
      guard !items.isEmpty else { return "[]" }
      var parts: [String] = []
      for item in items {
        guard let part = item.flatText else { return nil }
        parts.append(part)
      }
      return "[" + parts.joined(separator: ", ") + "]"
    case .string(let text): return Self.quoted(text)
    case .number(let text): return text
    case .bool(let flag): return flag ? "true" : "false"
    case .null: return "null"
    }
  }

  static func quoted(_ text: String) -> String {
    var output = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": output += "\\\""
      case "\\": output += "\\\\"
      case "\n": output += "\\n"
      case "\r": output += "\\r"
      case "\t": output += "\\t"
      case "\u{08}": output += "\\b"
      case "\u{0C}": output += "\\f"
      case _ where scalar.value < 0x20: output += String(format: "\\u%04x", scalar.value)
      default: output.unicodeScalars.append(scalar)
      }
    }
    return output + "\""
  }
}

extension OrderedJSON {
  /// A recursive-descent parser over UTF-8 bytes.
  private struct Parser {
    let bytes: [UInt8]
    var position = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { position >= bytes.count }

    func problem(_ message: String) -> Problem {
      Problem(description: "JSON text, byte \(position): \(message)")
    }

    func peek(_ character: Character) -> Bool {
      position < bytes.count && bytes[position] == character.asciiValue
    }

    mutating func skipSpace() {
      while position < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[position]) {
        position += 1
      }
    }

    mutating func value() throws -> OrderedJSON {
      guard position < bytes.count else { throw problem("the text ends early") }
      switch bytes[position] {
      case UInt8(ascii: "{"): return try object()
      case UInt8(ascii: "["): return try array()
      case UInt8(ascii: "\""): return .string(try string())
      case UInt8(ascii: "t"):
        try literal("true")
        return .bool(true)
      case UInt8(ascii: "f"):
        try literal("false")
        return .bool(false)
      case UInt8(ascii: "n"):
        try literal("null")
        return .null
      default: return try number()
      }
    }

    mutating func literal(_ word: String) throws {
      let expected = Array(word.utf8)
      guard bytes.count - position >= expected.count,
        Array(bytes[position..<position + expected.count]) == expected
      else { throw problem("expected \(word)") }
      position += expected.count
    }

    mutating func object() throws -> OrderedJSON {
      position += 1
      var members: [Member] = []
      skipSpace()
      if peek("}") {
        position += 1
        return .object([])
      }
      while true {
        skipSpace()
        guard peek("\"") else { throw problem("expected a member name") }
        let key = try string()
        skipSpace()
        guard peek(":") else { throw problem("expected :") }
        position += 1
        skipSpace()
        members.append(Member(key: key, value: try value()))
        skipSpace()
        if peek(",") {
          position += 1
        } else if peek("}") {
          position += 1
          return .object(members)
        } else {
          throw problem("expected , or }")
        }
      }
    }

    mutating func array() throws -> OrderedJSON {
      position += 1
      var items: [OrderedJSON] = []
      skipSpace()
      if peek("]") {
        position += 1
        return .array([])
      }
      while true {
        skipSpace()
        items.append(try value())
        skipSpace()
        if peek(",") {
          position += 1
        } else if peek("]") {
          position += 1
          return .array(items)
        } else {
          throw problem("expected , or ]")
        }
      }
    }

    mutating func string() throws -> String {
      position += 1
      var text = ""
      var run: [UInt8] = []
      func flush() throws {
        guard !run.isEmpty else { return }
        guard let chunk = String(bytes: run, encoding: .utf8) else {
          throw problem("a string is not UTF-8")
        }
        text += chunk
        run.removeAll()
      }
      while position < bytes.count {
        let byte = bytes[position]
        if byte == UInt8(ascii: "\"") {
          position += 1
          try flush()
          return text
        }
        if byte < 0x20 { throw problem("a control character in a string") }
        guard byte == UInt8(ascii: "\\") else {
          run.append(byte)
          position += 1
          continue
        }
        try flush()
        position += 1
        guard position < bytes.count else { break }
        let escape = bytes[position]
        position += 1
        switch escape {
        case UInt8(ascii: "\""): text += "\""
        case UInt8(ascii: "\\"): text += "\\"
        case UInt8(ascii: "/"): text += "/"
        case UInt8(ascii: "b"): text += "\u{08}"
        case UInt8(ascii: "f"): text += "\u{0C}"
        case UInt8(ascii: "n"): text += "\n"
        case UInt8(ascii: "r"): text += "\r"
        case UInt8(ascii: "t"): text += "\t"
        case UInt8(ascii: "u"): text.unicodeScalars.append(try unicodeEscape())
        default: throw problem("an unknown escape")
        }
      }
      throw problem("the text ends inside a string")
    }

    mutating func hexUnit() throws -> UInt32 {
      guard bytes.count - position >= 4,
        let digits = String(bytes: bytes[position..<position + 4], encoding: .utf8),
        let unit = UInt32(digits, radix: 16)
      else { throw problem("expected four hexadecimal digits") }
      position += 4
      return unit
    }

    mutating func unicodeEscape() throws -> Unicode.Scalar {
      let first = try hexUnit()
      if (0xD800...0xDBFF).contains(first) {
        guard peek("\\"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "u")
        else {
          throw problem("a high surrogate without a low surrogate")
        }
        position += 2
        let second = try hexUnit()
        guard (0xDC00...0xDFFF).contains(second),
          let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
        else { throw problem("a high surrogate without a low surrogate") }
        return scalar
      }
      guard let scalar = Unicode.Scalar(first) else { throw problem("a lone low surrogate") }
      return scalar
    }

    mutating func digits() -> Int {
      let begin = position
      while position < bytes.count, (0x30...0x39).contains(bytes[position]) { position += 1 }
      return position - begin
    }

    mutating func number() throws -> OrderedJSON {
      let start = position
      if peek("-") { position += 1 }
      if peek("0") {
        position += 1
      } else if digits() == 0 {
        throw problem("expected a value")
      }
      if peek(".") {
        position += 1
        guard digits() > 0 else { throw problem("expected digits after the decimal point") }
      }
      if peek("e") || peek("E") {
        position += 1
        if peek("+") || peek("-") { position += 1 }
        guard digits() > 0 else { throw problem("expected digits in the exponent") }
      }
      guard let text = String(bytes: bytes[start..<position], encoding: .utf8) else {
        throw problem("a number is not UTF-8")
      }
      return .number(text)
    }
  }
}

extension OrderedJSON {
  /// The order of the top-level members of a Controller file and a ControllerPatch file, and of a
  /// patch's `selector`.
  static let recordKeys: OrderedJSON = .object(
    ["apiVersion", "kind", "vendorID", "productID", "selector", "modes", "patch"].map { key in
      let selector: [Member] = [
        Member(key: "vendorID", value: .null), Member(key: "productID", value: .null),
      ]
      return Member(key: key, value: key == "selector" ? .object(selector) : .null)
    }
  )
}
