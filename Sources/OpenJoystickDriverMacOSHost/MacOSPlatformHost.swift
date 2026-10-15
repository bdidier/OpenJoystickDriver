import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService
import OpenJoystickDriverUSB

/// The macOS host adapter: the system-extension, USB, and application services the neutral command
/// grammar reaches through `PlatformHost`.
package struct MacOSPlatformHost: PlatformHost {
  package init() {}

  package var extensionBundleIdentifier: String { ExtensionProbe.bundleIdentifier }

  package func extensionStatus(bundleURL: URL) -> ExtensionStatus {
    ExtensionProbe.currentStatus(bundleURL: bundleURL)
  }

  package func requestExtensionActivation() async -> SystemExtensionSetupRequestResult {
    await DefaultSystemExtensionSetupClient().requestActivation()
  }

  package func requestExtensionDeactivation() async -> SystemExtensionSetupRequestResult {
    await DefaultSystemExtensionSetupClient().requestDeactivation()
  }

  package func countVendorSpecificUSBControllers() async throws -> Int {
    try await USBControllerScanner.scanVendorSpecific(
      using: OpenJoystickDriverUSBTransportProvider()
    ).count
  }

  package func extensionEntitlementCovers(vendorID: UInt16, productID: UInt16) -> Bool {
    vendorID == USBDriverKitExtensionConfiguration.microsoftVendorID
      && USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(productID)
  }

  @MainActor
  package func runApplication() -> Never {
    let host = HeadlessApplicationHost()
    host.run()
  }
}
