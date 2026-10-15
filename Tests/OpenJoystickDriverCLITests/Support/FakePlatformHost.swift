import Foundation
import OpenJoystickDriverKit

/// A `PlatformHost` that reports an absent extension and no USB controllers, so command tests
/// never touch real USB or `systemextensionsctl`.
struct FakePlatformHost: PlatformHost {
  var extensionBundleIdentifier: String { "com.openjoystickdriver.fake-extension" }

  func extensionStatus(bundleURL: URL) -> ExtensionStatus {
    ExtensionStatus(bundle: .missing, registration: .absent)
  }

  func requestExtensionActivation() async -> SystemExtensionSetupRequestResult { .failed }

  func requestExtensionDeactivation() async -> SystemExtensionSetupRequestResult { .failed }

  func countVendorSpecificUSBControllers() async throws -> Int { 0 }

  func extensionEntitlementCovers(vendorID: UInt16, productID: UInt16) -> Bool { false }

  @MainActor
  func runApplication() -> Never { fatalError("Tests never run the application.") }
}
