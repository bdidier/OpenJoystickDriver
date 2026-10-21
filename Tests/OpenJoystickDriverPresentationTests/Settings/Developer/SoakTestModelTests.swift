import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct SoakTestFormTests {
  @Test
  func theFormStartsAtTheValuesOfTheCommand() throws {
    let settings = try SoakTestForm().settings().get()

    #expect(
      settings
        == SoakTestSettings(
          seconds: 60,
          intervalMilliseconds: 1_000,
          residentLimitMiB: 0,
          footprintLimitMiB: 512
        )
    )
  }

  @Test
  func theLimitsBecomeTheHealthPolicyWhereZeroMeansNoLimit() throws {
    var form = SoakTestForm()
    form.residentLimit = "300"
    form.footprintLimit = "0"
    let policy = try form.settings().get().policy

    #expect(policy.maximumResidentBytes == 300 * 1_048_576)
    #expect(policy.maximumPhysicalFootprintBytes == nil)
  }

  @Test
  func textThatIsNotAWholeNumberNamesItsField() {
    var form = SoakTestForm()
    form.interval = "fast"

    #expect(form.settings() == .failure(.notANumber(.interval)))
    form.interval = "1.5"
    #expect(form.settings() == .failure(.notANumber(.interval)))
    form.interval = ""
    #expect(form.settings() == .failure(.notANumber(.interval)))
  }

  @Test
  func everyFieldIsHeldToTheRangeOfItsOption() {
    let outOfRange: [(SoakTestField, String)] = [
      (.seconds, "0"), (.seconds, "86401"), (.interval, "99"), (.interval, "60001"),
      (.residentLimit, "-1"), (.residentLimit, "65537"), (.footprintLimit, "65537"),
    ]
    for (field, text) in outOfRange {
      var form = SoakTestForm()
      switch field {
      case .seconds: form.seconds = text
      case .interval: form.interval = text
      case .residentLimit: form.residentLimit = text
      case .footprintLimit: form.footprintLimit = text
      }
      #expect(form.settings() == .failure(.outOfRange(field)), "\(field) \(text)")
    }
    var edges = SoakTestForm()
    edges.seconds = "1"
    edges.interval = "60000"
    edges.residentLimit = "65536"
    #expect((try? edges.settings().get()) != nil)
  }

  @Test
  func aRunOfTooManySamplesIsRefused() {
    var form = SoakTestForm()
    form.seconds = "86400"
    form.interval = "100"

    #expect(form.settings() == .failure(.tooManySamples(864_001)))
  }

  @Test
  func theProblemMessageNamesTheFieldAndItsRange() {
    let label = OJDLocalized.string(SoakTestField.interval.labelKey)

    #expect(
      SoakTestProblem.outOfRange(.interval).message
        == OJDLocalized.formatted("developer.soakOutOfRange", label, 100, 60_000)
    )
    #expect(SoakTestProblem.outOfRange(.interval).message.contains(label))
  }
}

@Suite
@MainActor
struct SoakTestModelTests {
  private final class Recorder: @unchecked Sendable {
    var processIDs: [Int32] = []
    var settings: [SoakTestSettings] = []
  }

  private static func snapshot(
    _ availability: DiagnoseServiceSnapshot.Availability
  )
    -> DiagnoseServiceSnapshot
  {
    DiagnoseServiceSnapshot(
      availability: availability,
      status: nil,
      virtualDiagnostics: nil,
      frameTimings: nil
    )
  }

  private static func summary(
    residentBytes: UInt64,
    policy: RuntimeHealthPolicy = .standard
  ) throws -> RuntimeHealthSummary {
    let samples = (0..<7).map { index in
      RuntimeHealthSample(
        elapsedNanoseconds: UInt64(index) * 10_000_000_000,
        residentBytes: residentBytes,
        physicalFootprintBytes: residentBytes,
        cumulativeCPUNanoseconds: UInt64(index) * 1_000_000,
        fileDescriptorCount: 10,
        threadCount: 4
      )
    }
    return try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(samples, policy: policy)
    )
  }

  private static func model(
    availability: DiagnoseServiceSnapshot.Availability = .running,
    processID: Int32? = 4_242,
    recorder: Recorder = Recorder(),
    sample: @escaping @Sendable (Int32, SoakTestSettings) async throws -> RuntimeHealthSummary
  ) -> SoakTestModel {
    SoakTestModel(
      source: SoakTestModel.Source(
        snapshot: { snapshot(availability) },
        processIdentifier: { processID },
        sample: { processID, settings in
          recorder.processIDs.append(processID)
          recorder.settings.append(settings)
          return try await sample(processID, settings)
        }
      )
    )
  }

  private func finish(_ model: SoakTestModel) async {
    model.start()
    while model.isRunning { await Task.yield() }
  }

  @Test
  func aStableRunPassesAndSamplesTheServiceWithTheEnteredSettings() async throws {
    let recorder = Recorder()
    let summary = try Self.summary(residentBytes: 50 * 1_048_576)
    let model = Self.model(recorder: recorder) { _, _ in summary }
    model.form.seconds = "90"
    model.form.interval = "500"
    model.form.footprintLimit = "256"

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.id == "runtime-health")
    #expect(row.status == .pass)
    #expect(recorder.processIDs == [4_242])
    #expect(
      recorder.settings
        == [
          SoakTestSettings(
            seconds: 90,
            intervalMilliseconds: 500,
            residentLimitMiB: 0,
            footprintLimitMiB: 256
          )
        ]
    )
  }

  @Test
  func aLimitThatTheServiceExceedsFails() async throws {
    let policy = RuntimeHealthPolicy(residentLimitMiB: 0, footprintLimitMiB: 10)
    let summary = try Self.summary(residentBytes: 50 * 1_048_576, policy: policy)
    let model = Self.model { _, _ in summary }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .fail)
  }

  @Test
  func aStoppedServiceIsSkippedWithoutSampling() async {
    let recorder = Recorder()
    let model = Self.model(availability: .stopped, recorder: recorder) { _, _ in
      throw CancellationError()
    }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .skip)
    #expect(recorder.processIDs.isEmpty)
  }

  @Test
  func aServiceWithoutAProcessIsSkipped() async {
    let model = Self.model(processID: nil) { _, _ in throw CancellationError() }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .skip)
  }

  @Test
  func aSamplingFailureIsShownAsAFailure() async {
    let model = Self.model { _, _ in throw RuntimeHealthSamplingError.processUnavailable(4_242) }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .fail)
    #expect(row.detail == RuntimeHealthSamplingError.processUnavailable(4_242).errorDescription)
  }

  @Test
  func invalidSettingsDoNotStartARun() {
    let recorder = Recorder()
    let model = Self.model(recorder: recorder) { _, _ in throw CancellationError() }
    model.form.seconds = "0"

    model.start()

    #expect(model.state == .idle)
    #expect(model.problem == .outOfRange(.seconds))
    #expect(recorder.processIDs.isEmpty)
  }

  @Test
  func stoppingARunShowsTheEntryAgainWithoutAResult() async {
    let model = Self.model { _, _ in
      try await Task.sleep(nanoseconds: 60_000_000_000)
      throw CancellationError()
    }

    model.start()
    #expect(model.isRunning)
    model.cancel()
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(model.state == .idle)
  }
}
