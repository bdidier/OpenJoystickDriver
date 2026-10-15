import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ErrorCodeTests {
  private struct Catalog: Decodable {
    struct Entry: Decodable {
      let code: String
      let domain: String
      let name: String
      let status: String
      let retiredIn: String?
      let wire: String?
    }
    let codes: [Entry]
  }

  private func repositoryResource(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Errors
      .deletingLastPathComponent()  // OpenJoystickDriverKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository root
      .appendingPathComponent(path)
  }

  @Test
  func theActiveCatalogEntriesAreTheCases() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.json"))
    let active = try JSONDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.status == "active"
    }
    #expect(active.map(\.code) == ErrorCode.allCases.map(\.rawValue))
    #expect(active.map(\.name) == ErrorCode.allCases.map { "\($0)" })
    #expect(active.map(\.domain) == ErrorCode.allCases.map(\.domain.rawValue))
  }

  @Test
  func theRetiredCodesAreTheRetiredCatalogEntries() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.json"))
    let retired = try JSONDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.status == "retired"
    }
    #expect(RetiredErrorCode.all.map(\.code) == retired.map(\.code))
    #expect(RetiredErrorCode.all.map(\.domain.rawValue) == retired.map(\.domain))
    #expect(RetiredErrorCode.all.map(\.retiredIn) == retired.compactMap(\.retiredIn))
    #expect(RetiredErrorCode.named("e1003")?.retiredIn == "0.6.0-alpha.1")
    #expect(RetiredErrorCode.named("E1004") == nil)
  }

  @Test
  func theEndpointCodesKeepTheirNumbersAndTheHeaderCodesFollow() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.json"))
    let endpoint = try JSONDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.domain == "endpoint"
    }
    let numbers = Dictionary(uniqueKeysWithValues: endpoint.map { ($0.code, ($0.name, $0.status)) })
    let unchanged = [
      "E1001": "endpointDisabled", "E1002": "notGranted", "E1004": "invalidMessage",
      "E1005": "tooManyConnections", "E1006": "revoked", "E1007": "tooSlow",
      "E1008": "tooManyFeeds", "E1009": "feedClosed",
    ]
    for (code, name) in unchanged {
      #expect(numbers[code]?.0 == name && numbers[code]?.1 == "active", "\(code)")
    }
    #expect(numbers["E1003"]?.0 == "unsupportedProtocol" && numbers["E1003"]?.1 == "retired")
    #expect(ErrorCode(rawValue: "E1003") == nil)
    #expect(ErrorCode.unsupportedEndpointVersion.rawValue == "E1010")
    #expect(ErrorCode.unexpectedKind.rawValue == "E1011")
    #expect(ErrorCode.missingHeader.rawValue == "E1012")
    #expect(
      [ErrorCode.unsupportedEndpointVersion, .unexpectedKind, .missingHeader].allSatisfy {
        $0.domain == .endpoint
      }
    )
  }

  @Test
  func eachRemappingCodeIsTheCatalogEntryOfItsWireValue() throws {
    let data = try Data(contentsOf: repositoryResource("Resources/ErrorCodes.json"))
    let remapping = try JSONDecoder().decode(Catalog.self, from: data).codes.filter {
      $0.domain == "remapping" && $0.status == "active"
    }
    // One catalog entry per RPC code, in the declaration order of the enum.
    #expect(
      remapping.map(\.wire) == ApplicationServiceRemappingRPCError.Code.allCases.map(\.rawValue)
    )
    #expect(
      remapping.map(\.code)
        == ApplicationServiceRemappingRPCError.Code.allCases.map(\.errorCode.rawValue)
    )
  }

  @Test
  func everyCodeHasAnExplanationInTheTemplate() throws {
    let template = try String(
      contentsOf: repositoryResource(
        "Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings"
      ),
      encoding: .utf8
    )
    for code in ErrorCode.allCases {
      #expect(template.contains("\"error.\(code.rawValue)\" = "), "\(code.rawValue)")
    }
  }

  @Test
  func theExplanationIsLocalized() {
    for code in ErrorCode.allCases {
      #expect(code.localizedExplanation != "error.\(code.rawValue)")
    }
  }

  @Test
  func theRawValueIsTheWireValue() throws {
    let data = try JSONEncoder().encode([ErrorCode.tooSlow])
    #expect(String(bytes: data, encoding: .utf8) == "[\"E1007\"]")
  }
}
