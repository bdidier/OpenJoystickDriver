import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct StatusItemModelTests {
  private static let pad = StatusItemState.Controller(
    id: "pad-a",
    name: "Pad",
    isSuspended: false,
    isWireless: true
  )

  private static func state(
    controllers: [StatusItemState.Controller] = [],
    profiles: [StatusItemState.Profile] = []
  ) -> StatusItemState {
    StatusItemState(
      statusLine: "status",
      controllers: controllers,
      profiles: profiles,
      statusSymbolName: "circle"
    )
  }

  private static func entry(_ id: String, in entries: [StatusItemEntry]) -> StatusItemEntry? {
    for entry in entries {
      if entry.id == id { return entry }
      if let submenu = entry.submenu, let found = Self.entry(id, in: submenu) { return found }
    }
    return nil
  }

  private static func ids(_ entries: [StatusItemEntry]) -> [String] {
    entries.flatMap { [$0.id] + ids($0.submenu ?? []) }.filter {
      !$0.contains("profiles.activate.") && !$0.contains("profiles.deactivate.")
        && !$0.contains("activeProfile.")
    }
  }

  @Test
  func alreadyActiveProfileIsCheckedWithoutAnAction() throws {
    let active = StatusItemState.Profile(id: UUID(), name: "A", isActive: true)
    let other = StatusItemState.Profile(id: UUID(), name: "B", isActive: false)
    let entries = StatusItemModel.entries(
      for: Self.state(controllers: [Self.pad], profiles: [active, other])
    )
    let activeEntry = try #require(
      Self.entry("controllers.activeProfile.\(active.id.uuidString)", in: entries)
    )
    let otherEntry = try #require(
      Self.entry("controllers.activeProfile.\(other.id.uuidString)", in: entries)
    )
    #expect(activeEntry.isChecked)
    #expect(activeEntry.action == nil)
    #expect(!otherEntry.isChecked)
    #expect(otherEntry.action == .activateProfile(other.id))
  }

  @Test
  func noControllerDisablesControllerItemsAndKeepsThemVisible() throws {
    let entries = StatusItemModel.entries(for: Self.state())
    for id in [
      "controllers.suspend", "controllers.testInput", "controllers.activeProfile",
      "controllers.disconnectWireless", "controllers.showInWindow",
    ] {
      let item = try #require(Self.entry(id, in: entries))
      #expect(!item.isEnabled, "\(id)")
    }
    #expect(try #require(Self.entry("grantAccess", in: entries)).isEnabled)
    #expect(try #require(Self.entry("quit", in: entries)).isEnabled)
    #expect(!(try #require(Self.entry("profiles.activate", in: entries))).isEnabled)
    #expect(!(try #require(Self.entry("profiles.deactivate", in: entries))).isEnabled)
  }

  @Test
  func oneWirelessControllerEnablesItsItems() throws {
    let profile = StatusItemState.Profile(id: UUID(), name: "Racing", isActive: true)
    let other = StatusItemState.Profile(id: UUID(), name: "Menu", isActive: false)
    let entries = StatusItemModel.entries(
      for: Self.state(controllers: [Self.pad], profiles: [profile, other])
    )
    let suspend = try #require(Self.entry("controllers.suspend", in: entries))
    #expect(suspend.isEnabled)
    #expect(suspend.action == .suspendController(sessionToken: "pad-a"))
    let disconnect = try #require(Self.entry("controllers.disconnectWireless", in: entries))
    #expect(disconnect.isEnabled)
    #expect(disconnect.action == .disconnectWireless(sessionToken: "pad-a"))
    #expect(try #require(Self.entry("controllers.testInput", in: entries)).isEnabled)
    #expect(try #require(Self.entry("controllers.showInWindow", in: entries)).isEnabled)
    let active = try #require(Self.entry("controllers.activeProfile", in: entries))
    #expect(active.isEnabled)
    #expect(active.submenu?.map(\.isChecked) == [true, false])
    let activate = try #require(Self.entry("profiles.activate", in: entries))
    #expect(activate.submenu?.map(\.action) == [.activateProfile(other.id)])
    let deactivate = try #require(Self.entry("profiles.deactivate", in: entries))
    #expect(deactivate.submenu?.map(\.action) == [.deactivateProfile(profile.id)])
  }

  @Test
  func suspendedControllerOffersResume() throws {
    let suspended = StatusItemState.Controller(
      id: Self.pad.id,
      name: Self.pad.name,
      isSuspended: true,
      isWireless: false
    )
    let entries = StatusItemModel.entries(for: Self.state(controllers: [suspended]))
    #expect(Self.entry("controllers.suspend", in: entries) == nil)
    let resume = try #require(Self.entry("controllers.resume", in: entries))
    #expect(resume.action == .resumeController(sessionToken: "pad-a"))
    let disconnect = try #require(Self.entry("controllers.disconnectWireless", in: entries))
    #expect(!disconnect.isEnabled)
  }

  @Test
  func wiredControllerLeavesDisconnectDisabled() throws {
    let wired = StatusItemState.Controller(
      id: "pad-b",
      name: "Wired",
      isSuspended: false,
      isWireless: false
    )
    let entries = StatusItemModel.entries(for: Self.state(controllers: [wired]))
    #expect(!(try #require(Self.entry("controllers.disconnectWireless", in: entries))).isEnabled)
  }

  @Test
  func layoutIsFixedAcrossStates() {
    let none = Self.ids(StatusItemModel.entries(for: Self.state()))
    let wireless = Self.ids(StatusItemModel.entries(for: Self.state(controllers: [Self.pad])))
    var errored = Self.state()
    errored.statusLine = "service unavailable"
    errored.statusSymbolName = "xmark.octagon"
    let error = Self.ids(StatusItemModel.entries(for: errored))
    #expect(none == error)
    // Suspend and Resume are one slot; every other id is identical.
    #expect(none == wireless)
    #expect(
      none == [
        "status", "separator.status", "controllers", "controllers.suspend",
        "controllers.testInput", "controllers.activeProfile", "controllers.disconnectWireless",
        "controllers.showInWindow", "profiles", "profiles.activate", "profiles.deactivate",
        "separator.profiles", "grantAccess", "openWindow", "settings", "separator.window", "help",
        "help.activityLog", "help.explainErrorCode", "help.reportProblem", "help.projectWebsite",
        "separator.help", "quit",
      ]
    )
  }

  @Test
  func errorStateShowsTheStatusLineAndKeepsAccessReachable() throws {
    var errored = Self.state()
    errored.statusLine = "Needs attention"
    let entries = StatusItemModel.entries(for: errored)
    let line = try #require(Self.entry("status", in: entries))
    #expect(line.title == .verbatim("Needs attention"))
    #expect(!line.isEnabled)
    #expect(try #require(Self.entry("grantAccess", in: entries)).action == .showArea(.access))
    #expect(
      try #require(Self.entry("help.activityLog", in: entries)).action == .showArea(.activity)
    )
  }

  @Test
  func typedBluetoothTransportDecidesWireless() {
    func device(
      _ transport: PhysicalTransport?,
      connection: String
    )
      -> ApplicationServiceDeviceDescription
    {
      ApplicationServiceDeviceDescription(
        name: "Pad",
        vendorID: 1,
        productID: 2,
        protocolBinding: ProtocolBindingID(.hidDescriptor),
        connection: connection,
        discoverySource: .rawUSB,
        serialNumber: nil,
        bindingResult: .hidDescriptorFixture,
        connectionState: ControllerConnectionState(
          transport: transport,
          backend: .hid,
          isConnected: true,
          power: .unknown
        )
      )
    }
    #expect(device(.bluetoothClassic, connection: "HID").supportsWirelessDisconnect)
    #expect(!device(.bluetoothLE, connection: "HID").supportsWirelessDisconnect)
    #expect(!device(.usb, connection: "Bluetooth").supportsWirelessDisconnect)
    #expect(!device(nil, connection: "Bluetooth").supportsWirelessDisconnect)
  }

  @Test
  func statusLineIsOneLocalizedFormatWithPositionalArguments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriverStatusLine-\(UUID().uuidString).bundle"
    )
    let resources = root.appendingPathComponent("Contents/Resources")
    for language in ["en-US", "ar-SA"] {
      try FileManager.default.createDirectory(
        at: resources.appendingPathComponent("\(language).lproj"),
        withIntermediateDirectories: true
      )
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let info = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>CFBundleIdentifier</key>
      <string>test.statusline</string></dict></plist>
      """
    try Data(info.utf8).write(to: root.appendingPathComponent("Contents/Info.plist"))
    try Data("\"menuBar.statusLine\" = \"%1$@ · %2$@ · %3$@\";\n".utf8).write(
      to: resources.appendingPathComponent("en-US.lproj/Localizable.strings")
    )
    try Data("\"menuBar.statusLine\" = \"%3$@ ، %2$@ ، %1$@\";\n".utf8).write(
      to: resources.appendingPathComponent("ar-SA.lproj/Localizable.strings")
    )
    let bundle = try #require(Bundle(path: root.path))

    let arabic = Localization(bundle: bundle, preferredLanguages: ["ar-SA"])
    #expect(
      StatusItemStatusLine.make(
        readiness: "A",
        controllers: "B",
        profile: "C",
        localization: arabic,
        locale: Locale(identifier: "ar_SA")
      ) == "C ، B ، A"
    )
    let english = Localization(bundle: bundle, preferredLanguages: ["en-US"])
    #expect(
      StatusItemStatusLine.make(
        readiness: "A",
        controllers: "B",
        profile: "C",
        localization: english,
        locale: Locale(identifier: "en_US")
      ) == "A · B · C"
    )
  }
}
