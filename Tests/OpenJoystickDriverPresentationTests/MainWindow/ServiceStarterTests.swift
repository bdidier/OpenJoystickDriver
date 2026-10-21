import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

private final class Counter: @unchecked Sendable {
  var opened: [URL] = []
  var polls = 0
}

struct ServiceStarterTests {
  private let bundle = URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app")

  private func starter(
    counter: Counter,
    runningAfterPolls: Int?,
    bundle: URL?,
    opens: Bool,
    timeout: Double = 5
  ) -> ServiceStarter {
    ServiceStarter(
      processIdentifier: {
        counter.polls += 1
        guard let runningAfterPolls else { return nil }
        return counter.polls > runningAfterPolls ? 1 : nil
      },
      bundleURL: { bundle },
      open: { url in
        counter.opened.append(url)
        return opens
      },
      timeout: timeout,
      pollNanoseconds: 1_000_000
    )
  }

  @Test
  func aRunningServiceIsNotStartedAgain() async throws {
    let counter = Counter()
    try await starter(counter: counter, runningAfterPolls: 0, bundle: bundle, opens: true).start()

    #expect(counter.opened.isEmpty)
  }

  @Test
  func aStoppedServiceOpensTheBundleAndWaitsForTheSocket() async throws {
    let counter = Counter()
    try await starter(counter: counter, runningAfterPolls: 3, bundle: bundle, opens: true).start()

    #expect(counter.opened == [bundle])
  }

  @Test
  func aCopyOutsideAnAppCannotStart() async {
    let counter = Counter()
    let starter = starter(counter: counter, runningAfterPolls: nil, bundle: nil, opens: true)

    await #expect(throws: ServiceStarter.Failure.noBundle) { try await starter.start() }
    #expect(counter.opened.isEmpty)
  }

  @Test
  func aRefusedOpenAndASilentServiceAreDistinctFailures() async {
    let refused = starter(counter: Counter(), runningAfterPolls: nil, bundle: bundle, opens: false)
    await #expect(throws: ServiceStarter.Failure.openFailed(bundle.path)) {
      try await refused.start()
    }
    let silent = starter(
      counter: Counter(),
      runningAfterPolls: nil,
      bundle: bundle,
      opens: true,
      timeout: 0.05
    )
    await #expect(throws: ServiceStarter.Failure.notReady) { try await silent.start() }
  }

  @Test
  func everyFailureHasLocalizedText() {
    for failure in [
      ServiceStarter.Failure.noBundle, .openFailed("/x"), .notReady,
    ] {
      #expect(!failure.message.isEmpty)
      #expect(!failure.message.hasPrefix("banner."))
      #expect(!failure.message.hasPrefix("cli."))
    }
  }
}
