import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension ProtocolClassifierTests {
  // MARK: - Protocol description documents

  @Test
  func protocolDescriptionDecodesItsSignatures() throws {
    let signatures = try ProtocolDescription.decode(
      protocolDescription(signature: #""variant": "usb", "interfaceNumber": 0"#),
      protocolID: .xboxGIP,
      fileName: "xbox.gip.json"
    ).interfaceSignatures
    #expect(
      signatures == [
        ProtocolInterfaceSignature(
          protocolID: .xboxGIP,
          variant: .usb,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x47,
          interfaceProtocol: 0xD0,
          requiredInterfaceNumber: 0
        )
      ]
    )
    #expect(ProtocolClassifier.signatures.count == 4)
  }

  @Test(
    arguments: [
      (
        #""variant": "usb", "endpoint": 129"#, "unknown field(s): endpoint",
        ErrorCode.invalidProtocolDescription
      ),
      (#""variant": "wired""#, "xbox.gip has no variant wired", ErrorCode.unknownProtocolVariant),
      (
        #""variant": "bluetooth""#, "xbox.gip has no variant bluetooth",
        ErrorCode.unknownProtocolVariant
      ),
    ]
  )
  func protocolDescriptionRejectsABadSignature(
    signature: String,
    problem: String,
    code: ErrorCode
  ) {
    let error = #expect(throws: ProtocolDescriptionProblem.self) {
      try ProtocolDescription.decode(
        protocolDescription(signature: signature),
        protocolID: .xboxGIP,
        fileName: "xbox.gip.json"
      )
    }
    #expect(error?.code == code)
    #expect(error?.detail.hasPrefix("xbox.gip.json: ") == true)
    #expect(error?.description.contains(problem) == true)
  }

  @Test
  func protocolDescriptionRejectsABadHeader() {
    let cases: [(Data, String, ErrorCode)] = [
      (
        protocolDescription(signature: #""variant": "usb""#, extra: #""vendorID": 1118,"#),
        "unknown field(s): vendorID",
        .invalidProtocolDescription
      ),
      (
        protocolDescription(
          signature: #""variant": "usb""#,
          apiVersion: "unsupported.example/v9"
        ),
        "apiVersion unsupported.example/v9 is not supported; "
          + "the supported apiVersion is \(OpenJoystickDriverAPI.version)",
        .unsupportedAPIVersion
      ),
      (
        protocolDescription(signature: #""variant": "usb""#, kind: "Controller"),
        "expected \(ProtocolDescription.kind), found Controller",
        .invalidProtocolDescription
      ),
      (
        protocolDescription(signature: #""variant": "usb""#, family: "xbox.xusb"),
        "family must be xbox.gip",
        .protocolDescriptionFamilyMismatch
      ),
    ]
    for (data, problem, code) in cases {
      let error = #expect(throws: ProtocolDescriptionProblem.self) {
        try ProtocolDescription.decode(
          data,
          protocolID: .xboxGIP,
          fileName: "xbox.gip.json"
        )
      }
      #expect(error?.code == code)
      #expect(error?.detail.contains(problem) == true)
    }
  }

  @Test
  func protocolDescriptionSchemaAdmitsExactlyEachFamilysVariants() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent(
      "Resources/Schemas/protocol-description.schema.json"
    )
    let schema = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    let definitions = schema["$defs"] as? [String: Any]
    let signature = definitions?["interfaceSignature"] as? [String: Any]
    let variant = (signature?["properties"] as? [String: Any])?["variant"] as? [String: Any]
    #expect(variant?["enum"] as? [String] == PhysicalProtocolVariantID.allCases.map(\.rawValue))

    var rules: [String: Any] = [:]
    for rule in try #require(schema["allOf"] as? [[String: Any]]) {
      let condition = (rule["if"] as? [String: Any])?["properties"] as? [String: Any]
      // The generic rules (record sections, raw USB) name no family.
      guard let family = (condition?["family"] as? [String: Any])?["const"] as? String else {
        continue
      }
      let then = (rule["then"] as? [String: Any])?["properties"] as? [String: Any]
      rules[family] = then?["interfaceSignatures"]
    }
    #expect(Set(rules.keys) == Set(PhysicalProtocolID.allCases.map(\.rawValue)))
    for protocolID in PhysicalProtocolID.allCases {
      if protocolID.variants.isEmpty {
        // A family with no variants has no signatures to list: the schema forbids the field.
        #expect(rules[protocolID.rawValue] as? Bool == false, "\(protocolID.rawValue)")
      } else {
        let signatures = rules[protocolID.rawValue] as? [String: Any]
        let items = (signatures?["items"] as? [String: Any])?["properties"] as? [String: Any]
        let allowed = (items?["variant"] as? [String: Any])?["enum"] as? [String]
        #expect(allowed == protocolID.variants.map(\.rawValue), "\(protocolID.rawValue)")
      }
    }
  }

  // MARK: - Helpers

  func protocolDescription(
    signature: String,
    extra: String = "",
    apiVersion: String = OpenJoystickDriverAPI.version,
    kind: String = ProtocolDescription.kind,
    family: String = "xbox.gip"
  ) -> Data {
    Data(
      """
      {
        \(extra)
        "apiVersion": "\(apiVersion)",
        "kind": "\(kind)",
        "family": "\(family)",
        "endpoints": {"in": 130, "out": 2},
        "defaults": {"session": {"handshakeAttempts": 3, "announceResendLimit": 8}},
        "interfaceSignatures": [
          {\(signature), "interfaceClass": 255, "interfaceSubclass": 71, "interfaceProtocol": 208}
        ]
      }
      """.utf8
    )
  }
}
