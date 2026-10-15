import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension ProtocolClassifierTests {
  // MARK: - Protocol description documents

  @Test
  func protocolDescriptionDecodesItsSignatures() throws {
    let signatures = try ProtocolClassifier.interfaceSignatures(
      decoding: protocolDescription(signature: #""variant": "usb", "interfaceNumber": 0"#),
      protocolID: .xboxGIP,
      fileName: "xbox.gip.json"
    )
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
      (#""variant": "usb", "endpoint": 129"#, "unknown field(s): endpoint"),
      (#""variant": "wired""#, "xbox.gip has no variant wired"),
      (#""variant": "bluetooth""#, "xbox.gip has no variant bluetooth"),
    ]
  )
  func protocolDescriptionRejectsABadSignature(signature: String, problem: String) {
    let error = #expect(throws: ControllerRecordProblem.self) {
      try ProtocolClassifier.interfaceSignatures(
        decoding: protocolDescription(signature: signature),
        protocolID: .xboxGIP,
        fileName: "xbox.gip.json"
      )
    }
    #expect(error?.description.hasPrefix("xbox.gip.json: ") == true)
    #expect(error?.description.contains(problem) == true)
  }

  @Test
  func protocolDescriptionRejectsABadHeader() {
    let cases: [(Data, String)] = [
      (
        protocolDescription(signature: #""variant": "usb""#, extra: #""vendorID": 1118,"#),
        "unknown field(s): vendorID"
      ),
      (
        protocolDescription(
          signature: #""variant": "usb""#,
          apiVersion: "openjoystickdriver.io/v1beta1"
        ),
        "apiVersion openjoystickdriver.io/v1beta1 is not supported; the supported apiVersion is \(OpenJoystickDriverAPI.version)"
      ),
      (
        protocolDescription(signature: #""variant": "usb""#, kind: "Controller"),
        "expected \(ProtocolClassifier.protocolDescriptionKind), found Controller"
      ),
      (
        protocolDescription(signature: #""variant": "usb""#, family: "xbox.xusb"),
        "family must be xbox.gip"
      ),
    ]
    for (data, problem) in cases {
      let error = #expect(throws: ControllerRecordProblem.self) {
        try ProtocolClassifier.interfaceSignatures(
          decoding: data,
          protocolID: .xboxGIP,
          fileName: "xbox.gip.json"
        )
      }
      #expect(error?.description.contains(problem) == true)
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

    var rules: [String: [String: Any]] = [:]
    for rule in try #require(schema["allOf"] as? [[String: Any]]) {
      let condition = (rule["if"] as? [String: Any])?["properties"] as? [String: Any]
      let family = try #require((condition?["family"] as? [String: Any])?["const"] as? String)
      let then = (rule["then"] as? [String: Any])?["properties"] as? [String: Any]
      rules[family] = then?["interfaceSignatures"] as? [String: Any]
    }
    #expect(Set(rules.keys) == Set(PhysicalProtocolID.allCases.map(\.rawValue)))
    for protocolID in PhysicalProtocolID.allCases {
      let signatures = rules[protocolID.rawValue]
      if protocolID.variants.isEmpty {
        #expect(signatures?["maxItems"] as? Int == 0, "\(protocolID.rawValue)")
      } else {
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
    kind: String = ProtocolClassifier.protocolDescriptionKind,
    family: String = "xbox.gip"
  ) -> Data {
    Data(
      """
      {
        \(extra)
        "apiVersion": "\(apiVersion)",
        "kind": "\(kind)",
        "family": "\(family)",
        "interfaceSignatures": [
          {\(signature), "interfaceClass": 255, "interfaceSubclass": 71, "interfaceProtocol": 208}
        ]
      }
      """.utf8
    )
  }
}
