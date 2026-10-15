import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct SettingsStoreTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private func write(_ json: String, to location: DataLocation) throws {
    let url = root.fileURL(SettingsStore.fileName, in: location)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(json.utf8).write(to: url)
  }

  private func header(_ body: String = "") -> String {
    #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings"\#(body)}"#
  }

  @Test
  func everySettingRoundTripsThroughTheUserFile() throws {
    for key in ApplicationSettingKey.allCases {
      for value in [true, false] {
        try store.set(key, to: value)
        #expect(try store.value(of: key) == value, "\(key.rawValue)")
      }
    }
  }

  @Test
  func theDocumentEncodesAndDecodesToItself() throws {
    var document = SettingsDocument()
    for (index, key) in ApplicationSettingKey.allCases.enumerated() {
      document[key] = index.isMultiple(of: 2)
    }

    let decoded = try JSONDecoder().decode(
      SettingsDocument.self,
      from: JSONEncoder().encode(document)
    )

    #expect(decoded == document)
  }

  @Test
  func theUserFileCarriesTheHeaderAndTheDocumentedShape() throws {
    try store.update([.notifySounds: false, .updatesIncludePrereleases: true])

    let data = try Data(contentsOf: store.userFileURL)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(object["kind"] as? String == "Settings")
    #expect((object["notify"] as? [String: Bool]) == ["sounds": false])
    #expect((object["updates"] as? [String: Bool]) == ["includePrereleases": true])
  }

  @Test
  func missingFilesGiveTheBuiltInDefaults() throws {
    for key in ApplicationSettingKey.allCases {
      #expect(try store.value(of: key) == key.defaultValue, "\(key.rawValue)")
    }
  }

  @Test
  func theUserFileOverridesTheMachineFileWhichOverridesTheDefaults() throws {
    try write(
      header(
        #", "notify": {"sounds": false, "controllerConnected": true}, "developerTools": true"#
      ),
      to: .machineData
    )
    try write(header(#", "notify": {"controllerConnected": false}"#), to: .applicationData)

    #expect(try store.value(of: .notifySounds) == false)
    #expect(try store.value(of: .developerTools) == true)
    #expect(try store.value(of: .notifyControllerConnected) == false)
    #expect(try store.value(of: .notifyProfileActivated) == false)
  }

  @Test
  func writesNeverTouchTheMachineFile() throws {
    let machine = header(#", "developerTools": true"#)
    try write(machine, to: .machineData)

    try store.set(.developerTools, to: false)

    let machineURL = root.fileURL(SettingsStore.fileName, in: .machineData)
    #expect(try String(contentsOf: machineURL, encoding: .utf8) == machine)
    #expect(try store.value(of: .developerTools) == false)
    #expect(SettingsStore.writableLayer == .applicationData)
    #expect(SettingsStore.layers == [.machineData, .applicationData])
  }

  @Test
  func launchAtLoginIsStoredAsItsOpposite() throws {
    try store.set(.launchAtLogin, to: false)

    #expect(try store.launchAtLoginOptOut())
    let object = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: store.userFileURL))
        as? [String: Any]
    )
    #expect(object["launchAtLoginOptOut"] as? Bool == true)
    try store.set(.launchAtLogin, to: true)
    #expect(try store.launchAtLoginOptOut() == false)
  }

  @Test(arguments: [
    #"{"kind": "Settings"}"#,
    #"{"apiVersion": "openjoystickdriver/v0", "kind": "Settings"}"#,
  ])
  func aMissingOrUnsupportedAPIVersionIsE5001NamingTheFile(json: String) throws {
    try write(json, to: .applicationData)

    do {
      _ = try store.load()
      Issue.record("the file was accepted")
    } catch let SettingsStoreError.unsupported(problem) {
      #expect(problem.code == .unsupportedAPIVersion)
      #expect(problem.description.hasPrefix("E5001: "))
      #expect(problem.description.contains(store.userFileURL.path))
    }
  }

  @Test
  func aWrongKindIsRejectedWithoutACode() throws {
    try write(
      #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Profile"}"#,
      to: .machineData
    )

    do {
      _ = try store.load()
      Issue.record("the file was accepted")
    } catch let SettingsStoreError.unsupported(problem) {
      #expect(problem.code == nil)
      #expect(problem.description.contains("expected Settings, found Profile"))
    }
  }

  @Test(arguments: [
    "not json",
    #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Settings", "mystery": true}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Settings", "notify": {"mystery": 1}}"#,
    #"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Settings", "developerTools": "yes"}"#,
  ])
  func aDamagedFileIsAnErrorNotAnEmptyLayer(json: String) throws {
    try write(json, to: .applicationData)

    #expect(throws: SettingsStoreError.damaged(file: store.userFileURL.path)) {
      _ = try store.load()
    }
    #expect(throws: SettingsStoreError.self) { try store.set(.developerTools, to: true) }
  }
}
