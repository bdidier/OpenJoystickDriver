import Foundation

package enum SupportReportService {
  package static func make(
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    inputMonitoring: PermissionManager.AccessState,
    applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth?,
    applicationServiceInstalled: Bool,
    applicationServiceConnected: Bool,
    buildIdentity: BuildIdentity,
    systemGamepadAudit: SystemGamepadSupportAudit? = nil,
    frameTimings: [ControllerFrameTimings] = [],
    generatedAt: Date = Date()
  ) -> SupportReport {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    return SupportReport(
      generatedAt: generatedAt,
      buildIdentity: buildIdentity,
      osName: osName,
      osVersion: osVersion,
      architecture: architecture,
      inputMonitoring: inputMonitoring,
      applicationServiceInstalled: applicationServiceInstalled,
      applicationServiceConnected: applicationServiceConnected,
      applicationServiceHealth: applicationServiceHealth,
      systemGamepadAudit: systemGamepadAudit,
      frameTimings: frameTimings,
      status: status,
      virtualDiagnostics: virtualDiagnostics
    )
  }

  package static func defaultFilename(at date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "OpenJoystickDriver-support-\(formatter.string(from: date)).json"
  }

  package static func write(
    _ report: SupportReport,
    to outputURL: URL,
    overwrite: Bool = false
  ) throws {
    if !overwrite && FileManager.default.fileExists(atPath: outputURL.path) {
      throw NSError(
        domain: "OpenJoystickDriver.SupportReport",
        code: NSFileWriteFileExistsError,
        userInfo: [
          NSLocalizedDescriptionKey:
            "A file already exists at \(outputURL.path). Choose another output path."
        ]
      )
    }
    try report.encodedJSON().write(to: outputURL, options: .atomic)
  }

  private static var osName: String {
    #if os(macOS)
      return "macOS"
    #elseif os(Linux)
      return "Linux"
    #elseif os(Windows)
      return "Windows"
    #else
      return "unknown"
    #endif
  }

  private static var architecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }
}
