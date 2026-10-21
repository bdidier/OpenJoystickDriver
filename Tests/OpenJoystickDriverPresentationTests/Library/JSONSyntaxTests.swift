import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

struct JSONSyntaxTests {
  private func kinds(_ text: String) throws -> [(JSONSyntaxKind, String)] {
    try JSONSyntax.tokens(in: text).filter { $0.kind != .space }.map { ($0.kind, $0.text) }
  }

  private func expect(
    _ text: String,
    _ expected: [(JSONSyntaxKind, String)],
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let actual = try kinds(text)
    #expect(actual.map(\.0) == expected.map(\.0), sourceLocation: sourceLocation)
    #expect(actual.map(\.1) == expected.map(\.1), sourceLocation: sourceLocation)
  }

  @Test
  func everyTokenKindHasItsOwnRun() throws {
    try expect(
      "{\"k\": [\"v\", 1, true, false, null]}",
      [
        (.punctuation, "{"), (.key, "\"k\""), (.punctuation, ":"), (.punctuation, "["),
        (.string, "\"v\""), (.punctuation, ","), (.number, "1"), (.punctuation, ","),
        (.literal, "true"), (.punctuation, ","), (.literal, "false"), (.punctuation, ","),
        (.literal, "null"), (.punctuation, "]"), (.punctuation, "}"),
      ]
    )
  }

  @Test
  func runsJoinedGiveTheTextBack() throws {
    let text = "{\n  \"a\": [1, 2],\n  \"b\": {\n    \"c\": \"d\"\n  }\n}\n"
    #expect(try JSONSyntax.tokens(in: text).map(\.text).joined() == text)
  }

  @Test
  func aStringAfterAColonIsAValueAndAfterACommaInAnObjectIsAKey() throws {
    try expect(
      "{\"a\": \"b\", \"c\": \"d\"}",
      [
        (.punctuation, "{"), (.key, "\"a\""), (.punctuation, ":"), (.string, "\"b\""),
        (.punctuation, ","), (.key, "\"c\""), (.punctuation, ":"), (.string, "\"d\""),
        (.punctuation, "}"),
      ]
    )
  }

  @Test
  func stringsInAnArrayAreValuesEvenAfterAnObjectKey() throws {
    try expect(
      "{\"a\": [\"x\", \"y\"], \"b\": 1}",
      [
        (.punctuation, "{"), (.key, "\"a\""), (.punctuation, ":"), (.punctuation, "["),
        (.string, "\"x\""), (.punctuation, ","), (.string, "\"y\""), (.punctuation, "]"),
        (.punctuation, ","), (.key, "\"b\""), (.punctuation, ":"), (.number, "1"),
        (.punctuation, "}"),
      ]
    )
  }

  @Test
  func nestedContainersTrackDepth() throws {
    let tokens = try JSONSyntax.tokens(in: "{\"a\": {\"b\": [1]}}")
    let depths = tokens.filter { $0.kind == .key || $0.kind == .number }.map(\.depth)
    #expect(depths == [1, 2, 3])
    #expect(tokens.first?.depth == 0)
    #expect(tokens.last?.depth == 0)
  }

  @Test
  func escapesStayInsideTheStringRun() throws {
    let text = #""a\"b\\c\/d\n\t\u00e9\uD83D\uDE00""#
    try expect(text, [(.string, text)])
  }

  @Test
  func aKeyKeepsItsEscapes() throws {
    try expect(
      #"{"a\"b": 1}"#,
      [
        (.punctuation, "{"), (.key, #""a\"b""#), (.punctuation, ":"), (.number, "1"),
        (.punctuation, "}"),
      ]
    )
  }

  @Test
  func unicodeStaysInOneRun() throws {
    try expect("[\"é😀日本\"]", [(.punctuation, "["), (.string, "\"é😀日本\""), (.punctuation, "]")])
  }

  @Test(arguments: [
    "0", "-0", "12", "-12", "1.5", "-1.5", "1e3", "1E3", "-1.5e-3", "2.5E+10", "0.02",
  ])
  func numbersAreOneRun(_ number: String) throws {
    try expect("[\(number)]", [(.punctuation, "["), (.number, number), (.punctuation, "]")])
  }

  @Test
  func emptyContainers() throws {
    try expect(
      "{\"a\": {}, \"b\": []}",
      [
        (.punctuation, "{"), (.key, "\"a\""), (.punctuation, ":"), (.punctuation, "{"),
        (.punctuation, "}"), (.punctuation, ","), (.key, "\"b\""), (.punctuation, ":"),
        (.punctuation, "["), (.punctuation, "]"), (.punctuation, "}"),
      ]
    )
  }

  @Test(
    arguments: [
      "@", "{\"a\": }x", "[1,", "{", "]", "[}", "\"open", "\"bad\\q\"", "\"\\u12G4\"", "tru",
      "-", "1.", "1e", "01x", "nul", "1 2", "}", ":", "\"tab\there\"",
    ]
  )
  func unexpectedTextThrows(_ text: String) {
    #expect(throws: JSONSyntaxError.self) { try JSONSyntax.tokens(in: text) }
  }

  /// Text whose every token is well formed but sits where the JSON grammar does not allow it.
  @Test(
    arguments: [
      "[1 2]", "{,}", "{\"a\" 1}", "[1,]", "{\"a\": 1,}", "{\"a\"}", "[,1]", "{1: 2}",
      "\"a\": 1", "[] []", "{\"a\": 1 \"b\": 2}", "[1:2]", "{\"a\"::1}", "", "  ", "{\"a\": 1]",
    ]
  )
  func tokensOutOfGrammarThrow(_ text: String) {
    #expect(throws: JSONSyntaxError.self) { try JSONSyntax.tokens(in: text) }
  }

  @Test
  func theErrorSaysWhereItStoppedAndWhatJSONExpects() {
    #expect(
      throws: JSONSyntaxError(offset: 4, reason: "unexpected \"@\" where JSON expects a value")
    ) { try JSONSyntax.tokens(in: "[1, @]") }
    #expect(
      throws: JSONSyntaxError(
        offset: 1,
        reason: "unexpected \",\" where JSON expects a member name or }"
      )
    ) { try JSONSyntax.tokens(in: "{,}") }
    #expect(throws: JSONSyntaxError(offset: 0, reason: "the text holds no value")) {
      try JSONSyntax.tokens(in: "")
    }
  }
}
