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
      (protocolDescription(signature: #""variant": "usb""#, schema: "v1alpha1"), "unknown $schema"),
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

  // MARK: - Helpers

  func protocolDescription(
    signature: String,
    extra: String = "",
    schema: String = "v1beta1",
    family: String = "xbox.gip"
  ) -> Data {
    Data(
      """
      {
        \(extra)
        "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/\
      Resources/Schemas/\(schema)/protocol-description.schema.json",
        "family": "\(family)",
        "interfaceSignatures": [
          {\(signature), "interfaceClass": 255, "interfaceSubclass": 71, "interfaceProtocol": 208}
        ]
      }
      """.utf8
    )
  }
}
