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
/// It reads the format of ``OrderedJSON/formatted()``: one standard JSON value, any spacing. It
/// follows the JSON grammar, so a token where JSON does not allow it (`[1 2]`, `{,}`, `{"a" 1}`,
/// a trailing comma, a second top-level value) or a container left open or closed twice throws.
enum JSONSyntax {
  static func tokens(in text: String) throws(JSONSyntaxError) -> [JSONSyntaxToken] {
    var scanner = Scanner(scalars: Array(text.unicodeScalars))
    return try scanner.run()
  }

  /// What the grammar allows at the scanner's position.
  private enum Expectation: Equatable {
    /// A value: at the start, after `:`, or after `,` in an array.
    case value
    /// A value or `]`, after `[`.
    case valueOrClose
    /// A member name, after `,` in an object.
    case key
    /// A member name or `}`, after `{`.
    case keyOrClose
    /// `:`, after a member name.
    case colon
    /// `,` or the bracket that closes the container, after a value inside it.
    case commaOrClose
    /// Nothing but space, after the top-level value.
    case end
  }

  private struct Scanner {
    let scalars: [Unicode.Scalar]
    var position = 0
    var tokens: [JSONSyntaxToken] = []
    /// `true` for an object, `false` for an array.
    var containers: [Bool] = []
    var expectation = Expectation.value

    init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

    func failure(_ reason: String, at offset: Int? = nil) -> JSONSyntaxError {
      JSONSyntaxError(offset: offset ?? position, reason: reason)
    }

    var expectsValue: Bool { expectation == .value || expectation == .valueOrClose }

    mutating func run() throws(JSONSyntaxError) -> [JSONSyntaxToken] {
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
          guard expectsValue else { throw unexpected(scalar) }
          emit(.punctuation, from: position, length: 1)
          containers.append(scalar == "{")
          expectation = scalar == "{" ? .keyOrClose : .valueOrClose
          position += 1
        case "}", "]":
          let isObject = scalar == "}"
          guard containers.last == isObject,
            expectation == .commaOrClose || expectation == (isObject ? .keyOrClose : .valueOrClose)
          else { throw unexpected(scalar) }
          containers.removeLast()
          emit(.punctuation, from: position, length: 1)
          position += 1
          endValue()
        case ",":
          guard expectation == .commaOrClose, let isObject = containers.last else {
            throw unexpected(scalar)
          }
          expectation = isObject ? .key : .value
          emit(.punctuation, from: position, length: 1)
          position += 1
        case ":":
          guard expectation == .colon else { throw unexpected(scalar) }
          expectation = .value
          emit(.punctuation, from: position, length: 1)
          position += 1
        case "\"":
          let isKey = expectation == .key || expectation == .keyOrClose
          guard isKey || expectsValue else { throw unexpected(scalar) }
          let start = position
          try string()
          emit(isKey ? .key : .string, from: start)
          if isKey { expectation = .colon } else { endValue() }
        case "t", "f", "n":
          guard expectsValue else { throw unexpected(scalar) }
          let start = position
          try literal()
          emit(.literal, from: start)
          endValue()
        case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
          guard expectsValue else { throw unexpected(scalar) }
          let start = position
          try number()
          emit(.number, from: start)
          endValue()
        default:
          throw unexpected(scalar)
        }
      }
      guard containers.isEmpty else { throw failure("a container is not closed") }
      guard expectation == .end else { throw failure("the text holds no value") }
      return tokens
    }

    /// The failure for `scalar` where the grammar does not allow it.
    func unexpected(_ scalar: Unicode.Scalar) -> JSONSyntaxError {
      failure("unexpected \(String(scalar).debugDescription) where JSON expects \(expected)")
    }

    var expected: String {
      switch expectation {
      case .value: "a value"
      case .valueOrClose: "a value or ]"
      case .key: "a member name"
      case .keyOrClose: "a member name or }"
      case .colon: ":"
      case .commaOrClose: containers.last == true ? ", or }" : ", or ]"
      case .end: "the end of the text"
      }
    }

    /// A value ended: the container that holds it takes a comma or its closing bracket next.
    mutating func endValue() { expectation = containers.isEmpty ? .end : .commaOrClose }

    mutating func emit(_ kind: JSONSyntaxKind, from start: Int, length: Int? = nil) {
      let end = length.map { start + $0 } ?? position
      var text = String.UnicodeScalarView()
      text.append(contentsOf: scalars[start..<end])
      tokens.append(JSONSyntaxToken(kind: kind, text: String(text), depth: containers.count))
    }

    mutating func string() throws(JSONSyntaxError) {
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

    mutating func literal() throws(JSONSyntaxError) {
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

    mutating func number() throws(JSONSyntaxError) {
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
