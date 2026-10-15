import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Task 9.1e: the Switch 1 subcommand report, its rolling counter rule and its startup requests
/// come from `defaults.session.subcommands` in the family's description. The decoder accepts and
/// rejects the documents the Python validator does (the protocol description tests); the bytes
/// the driver sends are pinned in `Switch1SubcommandBytesTests`.
struct SubcommandDescriptionTests {
  private static let plain = #"{"subcommand": 3, "data": [48]}"#
  private static let factoryRead =
    #"{"subcommand": 16, "spiRead": {"address": 24608, "length": 24, "#
    + #""purpose": "factoryMotionCalibration"}}"#

  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", "endpoints": {"in": 130, "out": 2}, \(body)}
      """
    return try ProtocolDescription.decode(
      Data(json.utf8),
      protocolID: family,
      fileName: "\(family.rawValue).json"
    )
  }

  private func rejection(family: PhysicalProtocolID, _ body: String) -> ProtocolDescriptionProblem?
  {
    do {
      _ = try decode(family: family, body)
      return nil
    } catch { return error }
  }

  private func switch1(_ subcommands: String) -> String {
    #""defaults": {"session": {"subcommands": \#(subcommands)}}"#
  }

  private func plan(
    modulus: Int = 16,
    _ requests: [String]
  ) -> String {
    #"{"reportId": 1, "counterModulus": \#(modulus), "requests": [\#(requests.joined(separator: ","))]}"#
  }

  @Test
  func acceptsTheRequestsAndTheCounterRule() throws {
    let description = try decode(
      family: .nintendoSwitch1,
      switch1(plan(modulus: 4, [Self.plain, Self.factoryRead]))
    )
    let subcommands = try #require(description.subcommands)
    #expect(subcommands.reportID == 1)
    #expect(subcommands.requests.count == 2)
    #expect(subcommands.requests[0].data == [48])
    #expect(subcommands.requests[1].data == [32, 96, 0, 0, 24])
    #expect([0, 1, 2, 3, 4].map { subcommands.nextCounter(after: UInt8($0)) } == [1, 2, 3, 0, 1])
  }

  @Test
  func theBundledSwitch1DescriptionHoldsTheFiveStartupRequests() throws {
    let subcommands = try #require(
      PhysicalProtocolID.nintendoSwitch1.protocolDescription.subcommands
    )
    #expect(subcommands.counterModulus == 16)
    #expect(subcommands.requests.map(\.subcommand) == [3, 64, 72, 16, 16])
    #expect(
      subcommands.requests.map(\.data) == [
        [48], [1], [1], [32, 96, 0, 0, 24], [38, 128, 0, 0, 20],
      ]
    )
  }

  @Test
  func rejectsMalformedSubcommands() {
    let badRequests = [
      #"{"subcommand": 3}"#,
      #"{"subcommand": 3, "data": [1], "spiRead": {"address": 0, "length": 1, "#
        + #""purpose": "factoryMotionCalibration"}}"#,
      #"{"subcommand": 3, "data": []}"#,
      #"{"subcommand": 3, "data": [256]}"#,
      #"{"subcommand": 256, "data": [1]}"#,
      #"{"subcommand": 3, "data": [1], "extra": 1}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 0, "#
        + #""purpose": "factoryMotionCalibration"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 30, "#
        + #""purpose": "factoryMotionCalibration"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 4294967296, "length": 1, "#
        + #""purpose": "factoryMotionCalibration"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 1, "purpose": "other"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 1}}"#,
    ]
    for request in badRequests {
      #expect(
        rejection(family: .nintendoSwitch1, switch1(plan([request])))?.code
          == .invalidProtocolDescription,
        "\(request)"
      )
    }
    let bad = [
      plan(modulus: 1, [Self.plain]),
      plan(modulus: 257, [Self.plain]),
      plan([]),
      plan(Array(repeating: Self.plain, count: 17)),
      plan([Self.factoryRead, Self.factoryRead]),
      #"{"reportId": 1, "counterModulus": 16}"#,
      #"{"counterModulus": 16, "requests": [\#(Self.plain)]}"#,
      #"{"reportId": 1, "counterModulus": 16, "requests": [\#(Self.plain)], "extra": 1}"#,
    ]
    for subcommands in bad {
      #expect(
        rejection(family: .nintendoSwitch1, switch1(subcommands))?.code
          == .invalidProtocolDescription,
        "\(subcommands)"
      )
    }
  }

  @Test
  func onlySwitch1HasSubcommandsAndItMustHaveThem() {
    let body = switch1(plan([Self.plain]))
    #expect(rejection(family: .nintendoSwitch1, "")?.code == .invalidProtocolDescription)
    #expect(rejection(family: .xboxXID, body)?.code == .invalidProtocolDescription)
    #expect(rejection(family: .hidDescriptor, body)?.code == .invalidProtocolDescription)
  }
}
