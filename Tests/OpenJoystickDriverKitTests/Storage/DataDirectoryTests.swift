import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DataDirectoryTests {
  @Test
  func rootedDirectorySeparatesEveryLocationUnderItsRoot() {
    let root = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let directory = RootedDataDirectory(root: root)
    let urls = DataLocation.allCases.map { directory.url(for: $0) }
    #expect(Set(urls).count == DataLocation.allCases.count)
    #expect(urls.allSatisfy { $0.path.hasPrefix(root.path + "/") })
    #expect(
      directory.fileURL("a.json", in: .applicationData)
        == root.appendingPathComponent("applicationData/a.json")
    )
  }

  @Test
  func macOSDirectoryKeepsTheShippedLocations() {
    let directory = MacOSDataDirectory()
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(directory.url(for: .applicationData).path.hasSuffix("/OpenJoystickDriver"))
    #expect(directory.url(for: .logs).path == home + "/Library/Logs/OpenJoystickDriver")
    #expect(directory.url(for: .home).path == home)
    #expect(directory.url(for: .sharedTemporary).path == "/tmp")
    #expect(directory.url(for: .runtime).path.hasPrefix("/var/folders/"))
    #expect(
      directory.url(for: .applicationData).deletingLastPathComponent().path
        == home + "/Library/Application Support"
    )
    #expect(
      ControllerRecordSet.userDirectory
        == directory.url(for: .applicationData).appendingPathComponent("Controllers")
    )
    #expect(
      LocalServiceRPCTransport.defaultSocketPath == "/tmp/com.openjoystickdriver.\(geteuid()).rpc"
    )
  }

  @Test
  func logAndSocketPathsFollowTheInjectedDirectory() {
    let directory = RootedDataDirectory(
      root: MacOSDataDirectory().url(for: .temporary).appendingPathComponent(UUID().uuidString)
    )
    #expect(
      ApplicationServiceLogService.url(for: .standardError, dataDirectory: directory)
        == directory.url(for: .logs).appendingPathComponent("OpenJoystickDriver.err.log")
    )
    #expect(
      LocalServiceRPCTransport.socketPath(in: directory).hasPrefix(
        directory.url(for: .sharedTemporary).path
      )
    )
  }
}
