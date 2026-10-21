import Foundation

/// What a piece of record JSON text is, for coloring.
enum JSONSyntaxKind: Equatable, Sendable {
  /// An object member name, with its quotes.
  case key
  /// A string value, with its quotes.
  case string
  case number
  /// `true`, `false` or `null`.
  case literal
  /// `{ } [ ] , :`
  case punctuation
  /// Spaces and line breaks.
  case space
}

/// One run of the text. The runs of a text, joined, give the text back.
struct JSONSyntaxToken: Equatable, Sendable {
  let kind: JSONSyntaxKind
  let text: String
  /// How many objects and arrays enclose the token. A bracket is not inside the container it
  /// opens or closes.
  let depth: Int
}

/// Text the tokenizer cannot read. The app produces the text itself, so this is a programming
/// error, never user input.
struct JSONSyntaxError: Error, Equatable, CustomStringConvertible {
  /// The position in unicode scalars from the start of the text.
  let offset: Int
  let reason: String

  var description: String { "JSON text, scalar \(offset): \(reason)" }
}

/// Splits the JSON text the app produces into colorable runs.
///
/// It reads the format of ``OrderedJSON/formatted()``: standard JSON, any spacing. A character
/// JSON does not allow where it appears, or a container left open or closed twice, throws.
enum JSONSyntax {
  static func tokens(in text: String) throws -> [JSONSyntaxToken] {
    var scanner = Scanner(scalars: Array(text.unicodeScalars))
    return try scanner.run()
  }

  private struct Scanner {
    let scalars: [Unicode.Scalar]
    var position = 0
    var tokens: [JSONSyntaxToken] = []
    /// `true` for an object, `false` for an array.
    var containers: [Bool] = []
    var expectsKey = false
    var topLevelValues = 0

    init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

    func failure(_ reason: String, at offset: Int? = nil) -> JSONSyntaxError {
      JSONSyntaxError(offset: offset ?? position, reason: reason)
    }

    mutating func run() throws -> [JSONSyntaxToken] {
      while position < scalars.count {
        let scalar = scalars[position]
        switch scalar {
        case " ", "\n", "\r", "\t":
          let start = position
          while position < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[position]) {
            position += 1
          }
          emit(.space, from: start)
        case "{", "[":
          try beginValue()
          emit(.punctuation, from: position, length: 1)
          containers.append(scalar == "{")
          expectsKey = scalar == "{"
          position += 1
        case "}", "]":
          guard let isObject = containers.last, isObject == (scalar == "}") else {
            throw failure("\(scalar) closes nothing that is open")
          }
          containers.removeLast()
          expectsKey = false
          emit(.punctuation, from: position, length: 1)
          position += 1
        case ",":
          guard let isObject = containers.last else { throw failure("a comma outside a container") }
          expectsKey = isObject
          emit(.punctuation, from: position, length: 1)
          position += 1
        case ":":
          guard containers.last == true else { throw failure("a colon outside an object") }
          expectsKey = false
          emit(.punctuation, from: position, length: 1)
          position += 1
        case "\"":
          let isKey = expectsKey
          if !isKey { try beginValue() }
          let start = position
          try string()
          emit(isKey ? .key : .string, from: start)
          expectsKey = false
        case "t", "f", "n":
          try beginValue()
          let start = position
          try literal()
          emit(.literal, from: start)
        case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
          try beginValue()
          let start = position
          try number()
          emit(.number, from: start)
        default:
          throw failure("unexpected character \(String(scalar).debugDescription)")
        }
      }
      guard containers.isEmpty else { throw failure("a container is not closed") }
      return tokens
    }

    /// Counts a top-level value; a second one is a programming error.
    mutating func beginValue() throws {
      if containers.isEmpty {
        topLevelValues += 1
        guard topLevelValues == 1 else { throw failure("more than one top-level value") }
      }
    }

    mutating func emit(_ kind: JSONSyntaxKind, from start: Int, length: Int? = nil) {
      let end = length.map { start + $0 } ?? position
      var text = String.UnicodeScalarView()
      text.append(contentsOf: scalars[start..<end])
      tokens.append(JSONSyntaxToken(kind: kind, text: String(text), depth: containers.count))
    }

    mutating func string() throws {
      position += 1
      while position < scalars.count {
        let scalar = scalars[position]
        if scalar == "\"" {
          position += 1
          return
        }
        if scalar.value < 0x20 { throw failure("a control character in a string") }
        if scalar == "\\" {
          position += 1
          guard position < scalars.count else { break }
          switch scalars[position] {
          case "\"", "\\", "/", "b", "f", "n", "r", "t":
            position += 1
          case "u":
            position += 1
            for _ in 0..<4 {
              guard position < scalars.count, scalars[position].properties.isASCIIHexDigit else {
                throw failure("a \\u escape needs four hexadecimal digits")
              }
              position += 1
            }
          default:
            throw failure("an unknown escape \\\(scalars[position])")
          }
        } else {
          position += 1
        }
      }
      throw failure("a string is not closed")
    }

    mutating func literal() throws {
      for word in ["true", "false", "null"] {
        let expected = Array(word.unicodeScalars)
        if position + expected.count <= scalars.count,
          Array(scalars[position..<position + expected.count]) == expected
        {
          position += expected.count
          return
        }
      }
      throw failure("expected true, false or null")
    }

    mutating func digits() -> Int {
      let begin = position
      while position < scalars.count, ("0"..."9").contains(scalars[position]) { position += 1 }
      return position - begin
    }

    mutating func number() throws {
      if scalars[position] == "-" { position += 1 }
      if position < scalars.count, scalars[position] == "0" {
        position += 1
      } else if digits() == 0 {
        throw failure("a minus sign needs digits")
      }
      if position < scalars.count, scalars[position] == "." {
        position += 1
        guard digits() > 0 else { throw failure("a decimal point needs digits") }
      }
      if position < scalars.count, scalars[position] == "e" || scalars[position] == "E" {
        position += 1
        if position < scalars.count, scalars[position] == "+" || scalars[position] == "-" {
          position += 1
        }
        guard digits() > 0 else { throw failure("an exponent needs digits") }
      }
    }
  }
}
