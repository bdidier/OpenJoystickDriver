import Foundation
import OpenJoystickDriverKit

/// The actions of the Controllers detail that run longer than a click or end in a file: exporting
/// the virtual gamepad mapping, launching a game with it, and the timed captures.
@MainActor
final class ControllerDetailActions: ObservableObject {
  /// A capture that runs for a duration the user picks in a sheet.
  enum TimedKind: Identifiable, Equatable {
    case draftRecord
    case capturePackets

    var id: Self { self }
  }

  enum TimedState: Equatable {
    case idle
    case capturing
    case failed(String)
  }

  /// A file to ask the user where to save.
  struct SaveRequest: Equatable {
    let data: Data
    let fileName: String
    /// The folder the panel opens in, when it exists.
    let directory: URL?
    /// Said after the file is written, ahead of the file name.
    let summary: String?
  }

  /// The result of the latest action, shown under the action.
  struct Notice: Equatable {
    /// The action that ended in the notice, so each action shows only its own.
    enum Source: Equatable {
      case exportMapping
      case timedCapture
    }

    let source: Source
    let text: String
    let isError: Bool
  }

  @Published
  var timedKind: TimedKind?
  @Published
  private(set) var timedState: TimedState = .idle
  @Published
  private(set) var pendingSave: SaveRequest?
  @Published
  private(set) var notice: Notice?
  @Published
  private(set) var launchOutcome: VirtualGamepadLaunch.Outcome?

  private var timedTask: Task<Void, Never>?
  private var launched: Process?

  // MARK: - Timed captures

  /// Captures `device` for `seconds`, then asks for a place to save the result: the packets as
  /// JSON, or the record drafted from them. A failure stays in ``timedState`` for the sheet.
  func startTimed(
    _ kind: TimedKind,
    device: ApplicationServiceDeviceDescription,
    gateway: any ControllerDiagnosticsGateway,
    seconds: Double,
    descriptor: @escaping @Sendable () -> [UInt8]?
  ) {
    timedTask?.cancel()
    timedState = .capturing
    let descriptor = descriptor
    timedTask = Task { [weak self] in
      do {
        let packets = try await ControllerPacketCapture.collect(
          from: device,
          gateway: gateway,
          seconds: seconds
        )
        try Task.checkCancellation()
        self?.finishCapture(kind, device: device, packets: packets, descriptor: descriptor())
      } catch is CancellationError {
        self?.timedState = .idle
      } catch let error as ControllerRecordDrafting.NoLayout {
        self?.timedState = .failed(error.message)
      } catch { self?.timedState = .failed(RuntimePresentation.userFacingError(error)) }
    }
  }

  private func finishCapture(
    _ kind: TimedKind,
    device: ApplicationServiceDeviceDescription,
    packets: [PacketLogEntry],
    descriptor: [UInt8]?
  ) {
    do {
      switch kind {
      case .capturePackets:
        guard !packets.isEmpty else {
          timedState = .failed(OJDLocalized.string("cli.controller.capture.no_packets"))
          return
        }
        pendingSave = SaveRequest(
          data: try ControllerPacketCapture.exportData(packets),
          fileName: ControllerPacketCapture.fileName(for: device),
          directory: nil,
          summary: nil
        )
      case .draftRecord:
        let draft = try ControllerRecordDrafting.draft(
          for: device,
          packets: packets,
          descriptor: descriptor
        )
        let directory = ControllerRecordSet.userDirectory
        pendingSave = SaveRequest(
          data: draft.document,
          fileName: ControllerRecordDrafting.fileName(for: device),
          directory: FileManager.default.fileExists(atPath: directory.path) ? directory : nil,
          summary: OJDLocalized.formatted("cli.record.draft.captured", draft.capturedReports)
        )
      }
      timedState = .idle
      timedKind = nil
    } catch let error as ControllerRecordDrafting.NoLayout {
      timedState = .failed(error.message)
    } catch { timedState = .failed(RuntimePresentation.userFacingError(error)) }
  }

  /// Stops a running capture and closes the sheet.
  func cancelTimed() {
    timedTask?.cancel()
    timedTask = nil
    timedState = .idle
    timedKind = nil
  }

  /// Writes the pending file to `url`, or drops it when the user cancelled the panel.
  func finishSave(to url: URL?) {
    guard let request = pendingSave else { return }
    pendingSave = nil
    guard let url else { return }
    write(request.data, to: url, summary: request.summary, source: .timedCapture)
  }

  // MARK: - Export

  /// Writes the mapping of `profile` in `format` to `url`.
  func exportMapping(
    format: VirtualMappingFormat,
    profile: VirtualHIDProfileID,
    to url: URL
  ) {
    do {
      let text = try VirtualGamepadExport.document(format: format, profile: profile)
      write(Data(text.utf8), to: url, summary: nil, source: .exportMapping)
    } catch {
      notice = Notice(
        source: .exportMapping,
        text: RuntimePresentation.userFacingError(error),
        isError: true
      )
    }
  }

  private func write(
    _ data: Data,
    to url: URL,
    summary: String?,
    source: Notice.Source
  ) {
    do {
      try data.write(to: url, options: .atomic)
      let saved = OJDLocalized.formatted("controllers.fileSaved", url.lastPathComponent)
      notice = Notice(
        source: source,
        text: [summary, saved].compactMap { $0 }.joined(separator: " "),
        isError: false
      )
    } catch { notice = Notice(source: source, text: error.localizedDescription, isError: true) }
  }

  func clearNotice() { notice = nil }

  // MARK: - Launch

  /// Starts `program` with the mapping of every virtual gamepad in `devices`. The outcome shows
  /// that it started, why it could not, and with which status it ended.
  func launch(
    program: URL,
    devices: [ApplicationServiceDeviceDescription],
    gameControllerBackend: Bool,
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let name = program.deletingPathExtension().lastPathComponent
    do {
      let prepared = try VirtualGamepadLaunch.prepare(
        program: program,
        devices: devices,
        gameControllerBackend: gameControllerBackend,
        baseEnvironment: baseEnvironment
      )
      let process = ProgramExecutable.process(
        executable: prepared.executable,
        arguments: [],
        environment: prepared.environment,
        standardOutput: FileHandle.nullDevice
      )
      process.standardInput = FileHandle.nullDevice
      process.terminationHandler = { [weak self] finished in
        let status =
          finished.terminationReason == .uncaughtSignal
          ? 128 + finished.terminationStatus : finished.terminationStatus
        Task { @MainActor in
          self?.launchOutcome = .exited(program: name, status: status)
        }
      }
      try process.run()
      launched = process
      launchOutcome = .started(program: name)
    } catch let failure as VirtualGamepadLaunch.Failure {
      launchOutcome = .failed(failure.message)
    } catch {
      launchOutcome = .failed(
        VirtualGamepadLaunch.Failure.cannotStart(
          program: name,
          reason: error.localizedDescription
        ).message
      )
    }
  }
}
