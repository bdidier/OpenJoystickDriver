import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record text format: the bundled files are the reference, byte for byte.
struct OrderedJSONTests {
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Catalog
    .deletingLastPathComponent()  // Protocol
    .deletingLastPathComponent()  // OpenJoystickDriverKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()

  private static func recordFiles(under directory: String) throws -> [URL] {
    let root = repository.appendingPathComponent(directory)
    let walker = try #require(
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    )
    return (walker.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
      .sorted { $0.path < $1.path }
  }

  @Test
  func everyBundledRecordFileRoundTripsByteForByte() throws {
    var checked = 0
    for directory in [
      "Resources/Controllers", "Sources/OpenJoystickDriverKit/Resources/Controllers",
    ] {
      for url in try Self.recordFiles(under: directory) {
        let data = try Data(contentsOf: url)
        let text = try OrderedJSON.parse(data).formatted()
        #expect(text == String(bytes: data, encoding: .utf8), "\(url.path)")
        checked += 1
      }
    }
    #expect(checked > 600)
  }

  @Test
  func everyLoadedBundledRecordDocumentIsItsFileText() throws {
    for url in try Self.recordFiles(under: "Sources/OpenJoystickDriverKit/Resources/Controllers") {
      let document = try OrderedJSON.parse(Data(contentsOf: url))
      guard case .object(let members) = document,
        case .number(let vendor)? = members.first(where: { $0.key == "vendorID" })?.value,
        case .number(let product)? = members.first(where: { $0.key == "productID" })?.value,
        let vendorID = UInt16(vendor), let productID = UInt16(product)
      else {
        Issue.record("\(url.path) has no identity")
        continue
      }
      let record = ControllerRecordSet.bundled.records[
        ControllerModelID(vendorID: vendorID, productID: productID)
      ]
      #expect(record?.document == (try Data(contentsOf: url)), "\(url.path)")
    }
  }

  @Test
  func usesTheFileSpacing() throws {
    let text = try OrderedJSON.parse(Data(#"{"a":1,"b":[true,null],"c":{}}"#.utf8)).formatted()
    #expect(text == "{\n  \"a\": 1,\n  \"b\": [true, null],\n  \"c\": {}\n}\n")
  }

  @Test
  func arrayBreaksWhenItsLineWouldPass80Columns() throws {
    let word = String(repeating: "x", count: 30)
    let value = OrderedJSON.object([
      .init(key: "k", value: .array([.string(word), .string(word)]))
    ])
    // `  "k": ["` + 30 + `", "` + 30 + `"]` is 2 + 5 + 1 + 32 + 2 + 32 + 1 = 75 columns.
    #expect(value.formatted().contains("[\"\(word)\", \"\(word)\"]"))
    let wide = OrderedJSON.object([
      .init(key: "k", value: .array([.string(word + "yyyyyyyyyy"), .string(word)]))
    ])
    #expect(wide.formatted().contains("[\n    \"\(word)yyyyyyyyyy\",\n    \"\(word)\"\n  ]"))
  }

  @Test
  func objectMembersKeepTheOrderOfTheGuideThenSort() throws {
    let object: [String: Any] = ["z": 1, "a": 2, "m": 3, "b": 4]
    let guide = OrderedJSON.object([
      .init(key: "m", value: .null), .init(key: "z", value: .null),
    ])
    let text = try OrderedJSON(foundation: object, order: guide).formatted()
    #expect(text == "{\n  \"m\": 3,\n  \"z\": 1,\n  \"a\": 2,\n  \"b\": 4\n}\n")
  }

  @Test
  func foundationValuesKeepBooleansIntegersAndFractions() throws {
    let object: [String: Any] = ["flag": true, "count": 7, "ratio": 0.02, "none": NSNull()]
    let text = try OrderedJSON(foundation: object).formatted()
    #expect(
      text == "{\n  \"count\": 7,\n  \"flag\": true,\n  \"none\": null,\n  \"ratio\": 0.02\n}\n"
    )
  }

  @Test
  func stringsKeepEscapesAndUnicode() throws {
    let source = #"{"k":"a\"b\\c\/d\n\t\u0001é\ud83d\ude00"}"#
    let value = try OrderedJSON.parse(Data(source.utf8))
    #expect(value.formatted() == "{\n  \"k\": \"a\\\"b\\\\c/d\\n\\t\\u0001é😀\"\n}\n")
  }

  @Test
  func numbersKeepTheirText() throws {
    let value = try OrderedJSON.parse(Data("[-1.5e3, 0, 10E+2]".utf8))
    #expect(value.formatted() == "[-1.5e3, 0, 10E+2]\n")
  }

  @Test(arguments: ["", "{", "[1,]", "{\"a\" 1}", "01", "\"\\x\"", "nul", "[1] 2", "\"\\ud800\""])
  func malformedTextFails(_ text: String) {
    #expect(throws: OrderedJSON.Problem.self) { try OrderedJSON.parse(Data(text.utf8)) }
  }
}
