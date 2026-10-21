import Foundation

/// The record JSON of a Library record as the detail view shows it: the colored runs, and the
/// hexadecimal readings that sit beside the `vendorID` and `productID` lines.
///
/// ``copyText`` is the record document itself. The readings are not part of it, so selecting or
/// copying the shown text gives valid JSON.
struct LibraryRecordText: Equatable {
  /// The top-level members that carry an identifier.
  static let identifierKeys: Set<String> = ["\"vendorID\"", "\"productID\""]

  /// The document, exactly as the catalog holds it.
  let copyText: String
  let tokens: [JSONSyntaxToken]
  /// The lines of the document without line breaks, the last empty line left out.
  let lines: [String]
  /// The hexadecimal reading of the number on a line, such as `0x353D`, by line index.
  let identifierReadings: [Int: String]

  /// Reads `document`, which the catalog produced. Throws when it is not JSON the tokenizer reads.
  init(document: String) throws {
    copyText = document
    tokens = try JSONSyntax.tokens(in: document)
    var lines = document.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last?.isEmpty == true { lines.removeLast() }
    self.lines = lines

    var readings: [Int: String] = [:]
    var line = 0
    var pendingKey = false
    for token in tokens {
      switch token.kind {
      case .key:
        pendingKey = token.depth == 1 && Self.identifierKeys.contains(token.text)
      case .number:
        if pendingKey, let value = UInt16(token.text) {
          readings[line] = ProfileIdentifierInput.formatted(value)
        }
        pendingKey = false
      case .space:
        line += token.text.filter { $0 == "\n" }.count
      case .punctuation where token.text == ":":
        break
      default:
        pendingKey = false
      }
    }
    identifierReadings = readings
  }
}
