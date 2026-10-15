import XCTest

final class BridgeProcessTests: XCTestCase {
  private struct Result {
    let status: Int32
    let output: String
    let error: String
  }

  private func run(_ arguments: [String]) throws -> Result {
    let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
    let binary = products.appendingPathComponent("ojd-webrtc-bridge")
    XCTAssertTrue(
      FileManager.default.isExecutableFile(atPath: binary.path),
      "the bridge is not built next to the test bundle at \(binary.path)"
    )
    let process = Process()
    process.executableURL = binary
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Result(
      status: process.terminationStatus,
      output: String(decoding: outputData, as: UTF8.self),
      error: String(decoding: errorData, as: UTF8.self)
    )
  }

  func testHelpPrintsUsageToStandardOutputAndExitsZero() throws {
    let result = try run(["--help"])
    XCTAssertEqual(result.status, 0)
    XCTAssertTrue(result.output.hasPrefix("usage: ojd-webrtc-bridge"), result.output)
    XCTAssertEqual(result.error, "")
  }

  func testABadArgumentPrintsUsageToStandardErrorAndExitsNonZero() throws {
    let result = try run(["--bad"])
    XCTAssertEqual(result.status, 1)
    XCTAssertTrue(result.error.hasPrefix("usage: ojd-webrtc-bridge"), result.error)
    XCTAssertEqual(result.output, "")
  }
}
