import Foundation

/// One alternative mode of a controller model: the protocol it runs and the probes that must all
/// hold for it to be selected. The record's own `protocol` is the default mode and has no probes.
public struct ControllerMode: Equatable, Sendable {
  public let id: String
  public let physicalProtocolID: PhysicalProtocolID
  public let physicalProtocolVariant: PhysicalProtocolVariantID?
  public let parameters: ProtocolParameters
  public let gipStartupPackets: [String]
  public let gipKeepAlivePolicy: GIPKeepAlivePolicy
  public let assemblyPolicy: ControllerAssemblyPolicy?
  public let probes: [ControllerModeProbe]
}

extension DeviceRuntimeProfile {
  /// This profile running the named mode's protocol; the profile itself for nil, and nil for a
  /// mode the record does not have.
  func applying(modeID: String?) -> DeviceRuntimeProfile? {
    guard let modeID else { return self }
    guard let mode = modes.first(where: { $0.id == modeID }) else { return nil }
    var profile = self
    profile.physicalProtocolID = mode.physicalProtocolID
    profile.physicalProtocolVariant = mode.physicalProtocolVariant
    profile.parameters = mode.parameters
    profile.gipStartupPackets = mode.gipStartupPackets
    profile.gipKeepAlivePolicy = mode.gipKeepAlivePolicy
    profile.assemblyPolicy = mode.assemblyPolicy
    profile.modeID = modeID
    return profile
  }
}

/// How a model's mode was chosen.
public enum ControllerModeSelection: Equatable, Sendable {
  /// The record has no modes.
  case noModes
  /// Every probe of the named mode held.
  case matched(String)
  /// No mode's probes all held, so the default mode runs.
  case noModeMatched
  /// The device is not on an IOHID route, which is the only route a probe can read, so the
  /// default mode runs.
  case noProbeRoute
  /// A probe got no usable reply, so the default mode runs.
  case probeInconclusive(reportID: UInt8)

  /// The selected mode's ID; nil selects the default mode.
  public var modeID: String? {
    if case .matched(let id) = self { return id }
    return nil
  }
}

/// Picks a model's mode by reading its probes. Modes are tried in record order and the first
/// whose probes all hold wins. A probe without a usable reply ends the selection at the default
/// mode and never disables the controller.
public enum ControllerModeSelector {
  @preconcurrency
  public static func select(
    from profile: DeviceRuntimeProfile,
    model: ControllerModelID,
    backend: DeviceAccessBackend,
    reader: any ControllerModeProbeReader,
    log: @Sendable (String) -> Void = { print($0) }
  ) async -> ControllerModeSelection {
    guard !profile.modes.isEmpty else { return .noModes }
    let name = String(format: "%04X:%04X", model.vendorID, model.productID)
    guard backend == .ioHID else {
      log(
        "[DeviceManager] Mode probes of \(name) read HID feature reports; the \(backend.rawValue)"
          + " route has none, so the default mode is used"
      )
      return .noProbeRoute
    }
    // One read per report serves every probe of that report.
    var replies: [Int: PhysicalHIDReportResult<Data>] = [:]
    for mode in profile.modes {
      var held = true
      for probe in mode.probes {
        let key = Int(probe.reportID) * 65_536 + probe.length
        let reply: PhysicalHIDReportResult<Data>
        if let cached = replies[key] {
          reply = cached
        } else {
          reply = await reader.readFeatureReport(probe.request)
          replies[key] = reply
        }
        switch probe.verdict(for: reply) {
        case .satisfied: continue
        case .unsatisfied: held = false
        case .inconclusive:
          log(
            "[DeviceManager] Mode probe of \(name) got no reply for report=\(probe.reportID)"
              + " (mode \(mode.id)); using the default mode"
          )
          return .probeInconclusive(reportID: probe.reportID)
        }
        if !held { break }
      }
      if held {
        log("[DeviceManager] Mode probes of \(name) selected mode \(mode.id)")
        return .matched(mode.id)
      }
    }
    log("[DeviceManager] No mode probe of \(name) matched; using the default mode")
    return .noModeMatched
  }
}
