import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The repository checks over files in a scratch directory.
@Suite
struct RepositoryValidationTests {
  private static let protocols = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/OpenJoystickDriverKit/Resources/Protocols")

  private static func scratch(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepositoryValidationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private static func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  /// A directory named `name`, which the checks find as a `.json` file they cannot read.
  private static func unreadable(_ name: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: a file that cannot be read is fileAccessFailed

  @Test
  func aRecordPatchOrDescriptionThatCannotBeReadIsAFileAccessFailure() throws {
    try Self.scratch { directory in
      let records = directory.appendingPathComponent("records")
      let patches = directory.appendingPathComponent("patches")
      let descriptions = directory.appendingPathComponent("descriptions")
      let record = try Self.unreadable("04d2-162e.json", in: records)
      let patch = try Self.unreadable("all.patch.json", in: patches)
      let description = try Self.unreadable("xbox-xusb.json", in: descriptions)

      func unreadableFiles(_ problems: [RepositoryProblem]) -> [String] {
        problems.filter { $0.code == .fileAccessFailed }.map {
          URL(fileURLWithPath: $0.file).lastPathComponent
        }
      }

      let recordProblems = RepositoryValidation.records(in: records)
      #expect(unreadableFiles(recordProblems) == [record.lastPathComponent])
      #expect(recordProblems.count == 1)

      let patchProblems = RepositoryValidation.applyPatches(
        records: records,
        patches: patches,
        output: directory.appendingPathComponent("out")
      )
      #expect(
        Set(unreadableFiles(patchProblems))
          == [patch.lastPathComponent, record.lastPathComponent]
      )
      #expect(patchProblems.count == 2)

      let descriptionProblems = RepositoryValidation.descriptions(in: descriptions)
      #expect(unreadableFiles(descriptionProblems) == [description.lastPathComponent])
    }
  }

  @Test
  func aProfileOrPersonaThatCannotBeReadIsAFileAccessFailure() throws {
    try Self.scratch { directory in
      let missing = directory.appendingPathComponent("missing.json")
      let profile = try #require(RepositoryValidation.profile(at: missing))
      #expect(profile.file == missing.path)
      #expect(profile.code == .fileAccessFailed)
      let persona = try #require(RepositoryValidation.persona(at: missing))
      #expect(persona.code == .fileAccessFailed)

      let invalid = directory.appendingPathComponent("invalid.json")
      try Self.write(#"{"apiVersion": "ojd/v0", "kind": "Profile", "name": "Pad"}"#, to: invalid)
      #expect(RepositoryValidation.profile(at: invalid)?.code == .unsupportedAPIVersion)
    }
  }

  @Test
  func textThatIsNotJSONIsAnInvalidRecord() throws {
    try Self.scratch { directory in
      try Self.write("{", to: directory.appendingPathComponent("04d2-162e.json"))
      let problems = RepositoryValidation.records(in: directory)
      #expect(problems.map(\.code) == [.invalidControllerRecord])
    }
  }

  // MARK: descriptions come in family order

  @Test
  func descriptionProblemsComeInFamilyOrderWithAMissingFileAtItsFamilysPlace() throws {
    try Self.scratch { directory in
      for name in try FileManager.default.contentsOfDirectory(atPath: Self.protocols.path) {
        try FileManager.default.copyItem(
          at: Self.protocols.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      // Family order is XID, XUSB, GIP; file-name order is GIP, XID, XUSB.
      for stem in ["xbox-xid", "xbox-gip"] {
        let url = directory.appendingPathComponent("\(stem).json")
        var object = try #require(
          JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        object["unknownField"] = 1
        try JSONSerialization.data(withJSONObject: object).write(to: url)
      }
      try FileManager.default.removeItem(at: directory.appendingPathComponent("xbox-xusb.json"))

      let problems = RepositoryValidation.descriptions(in: directory)
      #expect(
        problems.map { URL(fileURLWithPath: $0.file).lastPathComponent }
          == ["xbox-xid.json", "xbox-xusb.json", "xbox-gip.json"]
      )
      #expect(
        problems.map(\.code) == [
          .invalidProtocolDescription, .invalidProtocolDescription, .invalidProtocolDescription,
        ]
      )
      #expect(problems[1].message == "xbox-xusb.json is missing from \(directory.path)")
    }
  }

  @Test
  func aDescriptionFileThatNamesNoFamilyIsReportedAfterTheFamilies() throws {
    try Self.scratch { directory in
      for name in try FileManager.default.contentsOfDirectory(atPath: Self.protocols.path) {
        try FileManager.default.copyItem(
          at: Self.protocols.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      try Self.write("{}", to: directory.appendingPathComponent("aaa-extra.json"))
      let problems = RepositoryValidation.descriptions(in: directory)
      #expect(
        problems.map { URL(fileURLWithPath: $0.file).lastPathComponent } == ["aaa-extra.json"]
      )
    }
  }

  // MARK: the bundled failure keeps the code

  @Test
  func aBundledRecordFailureLeadsWithTheFileAndTheCodeOfTheRule() throws {
    try Self.scratch { directory in
      let text =
        #"{"apiVersion": "ojd/v0", "kind": "Controller", "vendorID": 1234, "productID": 5678}"#
      let url = directory.appendingPathComponent("04d2-162e.json")
      try Self.write(text, to: url)
      let problem = try #require(ControllerRecordSet.loadCatalog([url]).problems.first)
      #expect(problem.code == .unsupportedAPIVersion)
      let failure = ControllerRecordSet.bundledFailure(problem)
      #expect(failure.code == .invalidControllerRecord)
      #expect(failure.description == "\(url.path): E5001: \(problem.message)")
      #expect(failure.description.contains("E5001: apiVersion ojd/v0 is not supported"))
    }
  }
}
