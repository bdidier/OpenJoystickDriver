import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB
import SwifterKit

private struct Arguments {
  let output: URL
  let shortVersion: String
  let buildVersion: String

  init(_ values: [String]) throws {
    var output: String?
    var shortVersion: String?
    var buildVersion: String?
    var index = 0
    while index < values.count {
      let option = values[index]
      guard index + 1 < values.count else { throw ArgumentError.missingValue(option) }
      let value = values[index + 1]
      switch option {
      case "--output": output = value
      case "--short-version": shortVersion = value
      case "--build-version": buildVersion = value
      default: throw ArgumentError.unknownOption(option)
      }
      index += 2
    }
    guard let output, let shortVersion, let buildVersion else { throw ArgumentError.usage }
    self.output = URL(fileURLWithPath: output, isDirectory: true)
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
  }
}

private enum ArgumentError: Error, CustomStringConvertible {
  case missingValue(String)
  case unknownOption(String)
  case usage

  var description: String {
    switch self {
    case .missingValue(let option): "missing value for \(option)"
    case .unknownOption(let option): "unknown option: \(option)"
    case .usage: "required arguments: --output PATH --short-version VERSION --build-version VERSION"
    }
  }
}

/// Records that ask for the extension but are outside Apple's `transport.usb` grant.
private struct OutsideGrantError: Error, CustomStringConvertible {
  let models: [ControllerModelID]

  var description: String {
    "ExtensionOwned records outside Apple's grant: "
      + models.map(\.description).joined(separator: ", ")
  }
}

do {
  let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
  let outsideGrant = USBDriverKitExtensionConfiguration.modelsOutsideGrant(
    extensionOwned: USBDriverKitExtensionConfiguration.extensionOwnedModels(
      in: ControllerRecordSet.bundled
    )
  )
  guard outsideGrant.isEmpty else { throw OutsideGrantError(models: outsideGrant) }
  try DriverExtensionGenerator.generate(
    configuration: USBDriverKitExtensionConfiguration.driver,
    options: DriverExtensionGenerationOptions(
      shortVersion: arguments.shortVersion,
      buildVersion: arguments.buildVersion,
      deploymentTarget: "21.0"
    ),
    at: arguments.output
  )
} catch DriverExtensionGenerationError.destinationExists(let path) {
  // Generation writes a complete project into a missing folder only, so an existing project is
  // never mixed with or overwritten by the generated one.
  FileHandle.standardError.write(
    Data(
      """
      DriverKit generation refused: \(path) already exists.
      Delete the folder or pass a path that does not exist.

      """.utf8
    )
  )
  exit(2)
} catch {
  FileHandle.standardError.write(Data("DriverKit generation failed: \(error)\n".utf8))
  exit(2)
}
