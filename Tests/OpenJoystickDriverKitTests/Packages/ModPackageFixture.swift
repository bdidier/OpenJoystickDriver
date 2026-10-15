import Foundation

@testable import OpenJoystickDriverKit

/// A temporary application-support folder with the user's `Controllers`, `Personas`, and
/// `Profiles` folders, the `Packages` store, and a `Staging` folder where packages are built.
struct ModPackageFixture {
  let root = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
    "ojd-packages-\(UUID().uuidString)",
    isDirectory: true
  )

  var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
  var personas: URL { root.appendingPathComponent("Personas", isDirectory: true) }
  var profiles: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
  var packages: URL { root.appendingPathComponent("Packages", isDirectory: true) }

  /// Runs `body` with a fixture and removes it afterwards.
  static func with(_ body: (Self) throws -> Void) throws {
    let fixture = Self()
    try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try body(fixture)
  }

  /// The store over `Packages`, running as `version`.
  func store(running version: String = "0.6.0") -> ModPackageStore {
    ModPackageStore(directory: packages, runningVersion: version)
  }

  /// A controller `add` record for an identity the bundled catalog does not have.
  static func record(_ vendorID: Int, _ productID: Int) throws -> (name: String, data: Data) {
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordSet.overrideKind,
      "operation": "add",
      "record": [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": vendorID,
        "productID": productID, "protocol": ["family": "xbox.gip"],
      ],
    ]
    return (
      String(format: "%04x-%04x.json", vendorID, productID),
      try JSONSerialization.data(withJSONObject: document)
    )
  }

  /// A persona that selects `descriptor` for one controller model.
  static func persona(
    _ vendorID: Int,
    _ productID: Int,
    descriptor: String = "hid-generic"
  ) -> (name: String, data: Data) {
    let text =
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","#
      + #""kind":"\#(VirtualHIDProfileOverrideStore.kind)","#
      + #""match":{"vendorID":\#(vendorID),"productID":\#(productID)},"#
      + #""descriptor":"\#(descriptor)"}"#
    return (String(format: "%04x-%04x.json", vendorID, productID), Data(text.utf8))
  }

  /// A remapping profile document.
  static func profile(
    id: UUID = UUID(),
    name: String
  ) throws -> (name: String, data: Data) {
    let profile = RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    return ("\(name).json", Data(try RemappingProfileFileStore.encodedJSON(profile).utf8))
  }

  /// Writes `files` into `folder/kind`.
  func write(_ files: [(name: String, data: Data)], kind: String, in folder: URL) throws {
    guard !files.isEmpty else { return }
    let directory = folder.appendingPathComponent(kind, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for file in files { try file.data.write(to: directory.appendingPathComponent(file.name)) }
  }

  /// A package folder in `Staging` whose manifest lists exactly the files it holds, unless
  /// `manifest` overrides a field.
  @discardableResult
  func makePackage(
    _ name: String = "arcade-pack",
    version: String = "1.0.0",
    requires: [String: Any] = ["minimum": "0.6.0"],
    records: [(name: String, data: Data)] = [],
    personas: [(name: String, data: Data)] = [],
    profiles: [(name: String, data: Data)] = [],
    manifest overrides: [String: Any] = [:]
  ) throws -> URL {
    let folder = root.appendingPathComponent("Staging/\(UUID().uuidString)/\(name)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try write(records, kind: "Controllers", in: folder)
    try write(personas, kind: "Personas", in: folder)
    try write(profiles, kind: "Profiles", in: folder)
    var manifest: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
      "version": version, "author": "Tester", "requires": requires,
    ]
    if !records.isEmpty { manifest["records"] = records.map(\.name) }
    if !personas.isEmpty { manifest["personas"] = personas.map(\.name) }
    if !profiles.isEmpty { manifest["profiles"] = profiles.map(\.name) }
    for (key, value) in overrides { manifest[key] = value }
    try JSONSerialization.data(withJSONObject: manifest).write(
      to: folder.appendingPathComponent("mod.json")
    )
    return folder
  }
}
