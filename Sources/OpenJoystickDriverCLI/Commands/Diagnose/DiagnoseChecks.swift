import Foundation
import OpenJoystickDriverKit

extension DiagnoseServiceSnapshot {
  /// Asks the service once; a stopped or failing service never throws. `frameSeconds` limits the
  /// frame timings to the frames read within that many seconds; nil asks for the whole ring.
  static func fetch(frameSeconds: Int?) async -> Self {
    let socketPath = ServiceConnection.socketPath
    do {
      return try await ServiceConnection.request { client in
        await gather(
          status: { try await client.getStatus() },
          virtualDiagnostics: { try await client.getVirtualDeviceDiagnostics() },
          frameTimings: { try await client.getFrameTimings(lastSeconds: frameSeconds) },
          classify: { error in
            let failure = ServiceConnection.failure(for: error)
            if let known = failure as? CLIFailure, known.code == .serviceUnavailable {
              return .stopped
            }
            return .failed((failure as? CLIFailure)?.message ?? failure.localizedDescription)
          },
          listenerFailure: { ServiceListenerFailure.read(socketPath: socketPath) }
        )
      }
    } catch let failure as CLIFailure where failure.code == .serviceUnavailable {
      return Self(
        availability: .stopped,
        status: nil,
        virtualDiagnostics: nil,
        frameTimings: nil,
        listenerFailure: ServiceListenerFailure.read(socketPath: socketPath)
      )
    } catch {
      let message = (error as? CLIFailure)?.message ?? error.localizedDescription
      return Self(
        availability: .failed(message),
        status: nil,
        virtualDiagnostics: nil,
        frameTimings: nil,
        listenerFailure: .absent
      )
    }
  }
}

/// The soak options of `ojd diagnose --soak`.
struct DiagnoseSoak: Sendable, Equatable {
  let seconds: Int
  let intervalMilliseconds: Int
  let residentLimitMiB: Int
  let footprintLimitMiB: Int
}

enum DiagnoseChecks {
  /// Every check in report order.
  static func run(
    snapshot: DiagnoseServiceSnapshot,
    extensionStatus: ExtensionStatus,
    soak: DiagnoseSoak?
  ) async -> [DiagnoseCheck] {
    let usb: Result<Int, any Error>
    do { usb = .success(try await DiagnoseCommand.usbProbe()) } catch { usb = .failure(error) }
    var checks = DiagnosticsService.checks(
      snapshot: snapshot,
      extensionStatus: extensionStatus,
      records: RecordStore.load(),
      virtualDevices: RecordStore.virtualDeviceFiles(),
      usb: usb
    )
    checks.append(hidInputDropsCheck(snapshot: snapshot))
    checks.append(await soakCheck(snapshot: snapshot, soak: soak))
    return checks
  }

  private static func hidInputDropsCheck(snapshot: DiagnoseServiceSnapshot) -> DiagnoseCheck {
    let id = "hid-input-drops"
    guard snapshot.availability == .running, let processID = ServiceConnection.processIdentifier()
    else { return DiagnosticsService.skipped(id, snapshot) }
    return DiagnosticsService.hidInputDropsCheck(DiagnoseCommand.hidDropProbe(processID))
  }

  private static func soakCheck(
    snapshot: DiagnoseServiceSnapshot,
    soak: DiagnoseSoak?
  ) async -> DiagnoseCheck {
    let id = "runtime-health"
    guard let soak else {
      return DiagnoseCheck(
        id,
        .skip,
        CLILocalized.text("cli.diagnose.group.soakNotRequested")
      )
    }
    guard snapshot.availability == .running, let processID = ServiceConnection.processIdentifier()
    else { return DiagnosticsService.skipped(id, snapshot) }
    let policy = RuntimeHealthPolicy(
      residentLimitMiB: soak.residentLimitMiB,
      footprintLimitMiB: soak.footprintLimitMiB
    )
    CLIOutput.stderr(
      CLILocalized.format(
        "cli.diagnose.group.soakProgress",
        Double(soak.seconds).durationText
      )
    )
    do {
      let summary = try await DiagnoseCommand.soakSampler(
        processID,
        soak.seconds,
        soak.intervalMilliseconds,
        policy
      )
      return DiagnosticsService.soakCheck(summary)
    } catch { return DiagnoseCheck(id, .fail, error.localizedDescription) }
  }
}
