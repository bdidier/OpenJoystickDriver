import OpenJoystickDriverKit
import OpenJoystickDriverMacOSHost

/// Installs the macOS host adapter; `main.swift` calls it before any command or application runs.
func installPlatformHost() {
  PlatformHosts.install(MacOSPlatformHost())
}
