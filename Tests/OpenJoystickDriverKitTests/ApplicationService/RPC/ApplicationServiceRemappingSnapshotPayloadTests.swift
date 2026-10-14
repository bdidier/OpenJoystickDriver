import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ApplicationServiceRemappingSnapshotPayloadTests {
  @Test
  func packageProfilesRoundTrip() throws {
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      packageProfiles: [
        ApplicationServiceRemappingPackageProfile(profileID: UUID(), package: "arcade-pack")
      ],
      postEventAccess: .granted
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceRemappingSnapshotPayload.self,
      from: try JSONEncoder().encode(payload)
    )

    #expect(decoded == payload)
  }

  /// A payload from a service that predates package profiles lists none.
  @Test
  func missingPackageProfilesDecodeAsNone() throws {
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      packageProfiles: [
        ApplicationServiceRemappingPackageProfile(profileID: UUID(), package: "arcade-pack")
      ],
      postEventAccess: .granted
    )
    var object = try #require(
      try JSONSerialization.jsonObject(with: try JSONEncoder().encode(payload)) as? [String: Any]
    )
    object.removeValue(forKey: "packageProfiles")

    let decoded = try JSONDecoder().decode(
      ApplicationServiceRemappingSnapshotPayload.self,
      from: try JSONSerialization.data(withJSONObject: object)
    )

    #expect(decoded.packageProfiles.isEmpty)
    #expect(decoded.postEventAccess == .granted)
  }
}
