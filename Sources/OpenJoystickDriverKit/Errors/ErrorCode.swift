import Foundation

/// The stable error codes of OpenJoystickDriver, listed in `Resources/ErrorCodes.json`.
///
/// A code never changes meaning and is never reused. Look codes up on the wiki page `Error-Codes`.
///
/// The E3xxx cases carry the names of `ApplicationServiceRemappingRPCError.Code`, except
/// `remappingUnexpected`, because `unexpected` names E2001. Case names are unique across areas.
public enum ErrorCode: String, Codable, Sendable, CaseIterable {
  case endpointDisabled = "E1001"
  case notGranted = "E1002"
  case invalidMessage = "E1003"
  case tooManyConnections = "E1004"
  case revoked = "E1005"
  case tooSlow = "E1006"
  case tooManyFeeds = "E1007"
  case feedClosed = "E1008"
  case unsupportedEndpointVersion = "E1009"
  case unexpectedKind = "E1010"
  case missingHeader = "E1011"
  case unexpected = "E2001"
  case unknownCommand = "E2002"
  case usage = "E2003"
  case serviceUnavailable = "E2004"
  case serviceTimeout = "E2005"
  case serviceRequestFailed = "E2006"
  case peerRejected = "E2007"
  case permissionMissing = "E2008"
  case confirmationRequired = "E2009"
  case aborted = "E2010"
  case invalidInputFile = "E2011"
  case notFound = "E2012"
  case controllerRequestFailed = "E2013"
  case installationProblem = "E2014"
  case systemRequestFailed = "E2015"
  case fileAccessFailed = "E2016"
  case unsignedClient = "E2017"
  case diagnoseFailed = "E2018"
  case updateCheckFailed = "E2019"
  case staleInstallation = "E2020"
  case installedCLIFailed = "E2021"
  case recordTestMismatch = "E2022"
  case claimUnsupported = "E2023"
  case unknownAccessClient = "E2024"
  case ungrantableClient = "E2025"
  case noAccessScope = "E2026"
  case serviceStopping = "E2027"
  case duplicateTokenName = "E2028"
  case invalidTokenName = "E2029"
  case invalidWebOrigin = "E2030"
  case webPortUnavailable = "E2031"
  case controlScopeWithOrigins = "E2032"
  case launchFailed = "E2033"
  case requestListenerStopped = "E2034"
  case damagedListenerFailureRecord = "E2035"
  case noApplicationAnswered = "E2036"
  case notificationsDenied = "E2037"
  case controllerUnavailable = "E3001"
  case joyConPairUnavailable = "E3002"
  case motionUnavailable = "E3003"
  case argumentTooLarge = "E3004"
  case corruptLibrary = "E3005"
  case duplicateName = "E3006"
  case invalidArguments = "E3007"
  case invalidProfile = "E3008"
  case librarySizeExceeded = "E3009"
  case profileAlreadyExists = "E3010"
  case profileUpdateConflict = "E3011"
  case profileCountExceeded = "E3012"
  case profileNotFound = "E3013"
  case responseEncodingFailed = "E3014"
  case responseTooLarge = "E3015"
  case routerEngineUnavailable = "E3016"
  case routerLibraryAndEngineUnavailable = "E3017"
  case routerLibraryUnavailable = "E3018"
  case routerShutDown = "E3019"
  case transactionUnreconciled = "E3020"
  case unreadableLibrary = "E3021"
  case profileRecoveryRequired = "E3022"
  case unwritableLibrary = "E3023"
  case remappingUnexpected = "E3024"
  case profileProducesNoOutput = "E3025"
  case motionGyroNotSelected = "E3026"
  case motionProfileInactive = "E3027"
  case motionSessionChanged = "E3028"
  case packageProfileReadOnly = "E3029"
  case invalidManifest = "E4001"
  case requiresExcludesVersion = "E4002"
  case invalidPackageContent = "E4003"
  case packageClash = "E4004"
  case packageAlreadyInstalled = "E4005"
  case packageNotInstalled = "E4006"
  case packageStoreUnwritable = "E4007"
  case unsupportedAPIVersion = "E5001"
  case invalidProtocolDescription = "E5002"
  case protocolDescriptionFamilyMismatch = "E5003"
  case unknownProtocolVariant = "E5004"
  case damagedAccessGrants = "E5005"
  case damagedPortKey = "E5006"
  case invalidControllerRecord = "E5007"

  /// The part of the product that raises a code; the first digit of the number.
  public enum Domain: String, CaseIterable, Sendable {
    case endpoint = "Endpoint"
    case commandLine = "CLI"
    case remapping = "Remapping"
    case mod = "Mod"
    case document = "Document"

    /// The start of every code of the domain: `E` and the domain's digit.
    public var codePrefix: String {
      switch self {
      case .endpoint: "E1"
      case .commandLine: "E2"
      case .remapping: "E3"
      case .mod: "E4"
      case .document: "E5"
      }
    }
  }

  public var domain: Domain {
    switch self {
    case .endpointDisabled, .notGranted, .invalidMessage, .tooManyConnections, .revoked, .tooSlow,
      .tooManyFeeds, .feedClosed, .unsupportedEndpointVersion, .unexpectedKind, .missingHeader:
      .endpoint
    case .unexpected, .unknownCommand, .usage, .serviceUnavailable, .serviceTimeout,
      .serviceRequestFailed, .peerRejected, .permissionMissing, .confirmationRequired, .aborted,
      .invalidInputFile, .notFound, .controllerRequestFailed, .installationProblem,
      .systemRequestFailed, .fileAccessFailed, .unsignedClient, .diagnoseFailed,
      .updateCheckFailed, .staleInstallation, .installedCLIFailed, .recordTestMismatch,
      .claimUnsupported, .unknownAccessClient, .ungrantableClient, .noAccessScope,
      .serviceStopping, .duplicateTokenName, .invalidTokenName, .invalidWebOrigin,
      .webPortUnavailable, .controlScopeWithOrigins, .launchFailed, .requestListenerStopped,
      .damagedListenerFailureRecord, .noApplicationAnswered, .notificationsDenied:
      .commandLine
    case .controllerUnavailable, .joyConPairUnavailable, .motionUnavailable, .argumentTooLarge,
      .corruptLibrary, .duplicateName, .invalidArguments, .invalidProfile, .librarySizeExceeded,
      .profileAlreadyExists, .profileUpdateConflict, .profileCountExceeded, .profileNotFound,
      .responseEncodingFailed, .responseTooLarge, .routerEngineUnavailable,
      .routerLibraryAndEngineUnavailable, .routerLibraryUnavailable, .routerShutDown,
      .transactionUnreconciled, .unreadableLibrary, .profileRecoveryRequired, .unwritableLibrary,
      .remappingUnexpected, .profileProducesNoOutput, .motionGyroNotSelected,
      .motionProfileInactive, .motionSessionChanged, .packageProfileReadOnly:
      .remapping
    case .invalidManifest, .requiresExcludesVersion, .invalidPackageContent, .packageClash,
      .packageAlreadyInstalled, .packageNotInstalled, .packageStoreUnwritable:
      .mod
    case .unsupportedAPIVersion, .invalidProtocolDescription, .protocolDescriptionFamilyMismatch,
      .unknownProtocolVariant, .damagedAccessGrants, .damagedPortKey, .invalidControllerRecord:
      .document
    }
  }

  /// What went wrong and how to fix it, in the language of the user.
  public var localizedExplanation: String {
    Localization().string("error.\(rawValue)")
  }
}

extension ErrorCode {
  /// The code that typed text names: surrounding whitespace and letter case do not matter.
  /// `ojd explain` and the app's Explain Error Code read codes through this.
  public init?(typed text: String) {
    self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
  }
}
