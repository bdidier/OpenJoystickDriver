import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

struct LibraryRecordTextTests {
  private static let document = """
    {
      "apiVersion": "openjoystickdriver/v1alpha1",
      "kind": "Controller",
      "vendorID": 13629,
      "productID": 4296,
      "modes": [
        {
          "id": "default",
          "vendorID": 99,
          "protocol": {
            "family": "XboxGIP"
          }
        }
      ]
    }

    """

  private func text() throws -> LibraryRecordText {
    try LibraryRecordText(document: Self.document)
  }

  @Test
  func onlyTheTopLevelVendorAndProductLinesGetAReading() throws {
    let text = try text()

    #expect(text.identifierReadings == [3: "0x353D", 4: "0x10C8"])
    #expect(text.lines[3] == "  \"vendorID\": 13629,")
    #expect(text.lines[4] == "  \"productID\": 4296,")
  }

  @Test
  func aNestedVendorIDGetsNoReading() throws {
    let text = try text()

    #expect(text.lines[8] == "      \"vendorID\": 99,")
    #expect(text.identifierReadings[8] == nil)
  }

  @Test
  func readingsUseUppercaseHexWithFourDigits() throws {
    let text = try LibraryRecordText(document: "{\n  \"vendorID\": 1,\n  \"productID\": 65535\n}\n")

    #expect(text.identifierReadings == [1: "0x0001", 2: "0xFFFF"])
  }

  @Test
  func aVendorIDKeyWithAStringValueGetsNoReading() throws {
    let text = try LibraryRecordText(document: "{\n  \"vendorID\": \"13629\"\n}\n")

    #expect(text.identifierReadings.isEmpty)
  }

  @Test
  func aNumberOutsideTheIdentifierRangeGetsNoReading() throws {
    let text = try LibraryRecordText(document: "{\n  \"vendorID\": 70000\n}\n")

    #expect(text.identifierReadings.isEmpty)
  }

  @Test
  func copyTextIsTheDocumentAndValidJSON() throws {
    let text = try text()

    #expect(text.copyText == Self.document)
    let object = try JSONSerialization.jsonObject(with: Data(text.copyText.utf8))
    #expect((object as? [String: Any])?["vendorID"] as? Int == 13629)
    #expect(!text.copyText.contains("0x"))
  }

  @Test
  func theShownLinesAreTheDocumentLinesWithNoReading() throws {
    let text = try text()

    #expect(text.lines.joined(separator: "\n") + "\n" == Self.document)
    #expect(text.lines.allSatisfy { !$0.contains("0x") })
    #expect(text.tokens.map(\.text).joined() == Self.document)
  }

  @Test
  func theHighlightedTextHoldsNoReading() throws {
    let text = try text()
    let shown = String(text.highlighted.characters)

    #expect(shown + "\n" == Self.document)
    #expect(!shown.contains("0x"))
  }

  @Test
  func everyKindHasAColorAndPunctuationRecedes() {
    let kinds: [JSONSyntaxKind] = [.key, .string, .number, .literal, .punctuation, .space]
    #expect(Set(kinds.map { $0.color }).count == kinds.count)
  }

  @Test
  func textTheTokenizerCannotReadThrows() {
    #expect(throws: JSONSyntaxError.self) { try LibraryRecordText(document: "{ vendorID: 1 }") }
  }
}
