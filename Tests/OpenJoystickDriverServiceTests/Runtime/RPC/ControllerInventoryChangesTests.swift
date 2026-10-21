import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.timeLimit(.minutes(1)))
struct ControllerInventoryChangesTests {
  @Test
  func aNilGenerationReadsTheCurrentOneAtOnce() async {
    let changes = ControllerInventoryChanges(center: NotificationCenter())

    #expect(await changes.wait(after: nil, holdSeconds: 30) == 0)
  }

  @Test
  func aWaitReturnsWithinOneSecondOfAnInventoryNotification() async {
    let center = NotificationCenter()
    let changes = ControllerInventoryChanges(center: center)
    let clock = ContinuousClock()

    let start = clock.now
    async let generation = changes.wait(after: 0, holdSeconds: 30)
    try? await Task.sleep(nanoseconds: 50_000_000)
    center.post(name: .ojdControllerInventoryDidChange, object: nil)

    #expect(await generation == 1)
    #expect(clock.now - start < .seconds(1))
  }

  @Test
  func aChangeBeforeTheWaitAnswersAtOnce() async {
    let center = NotificationCenter()
    let changes = ControllerInventoryChanges(center: center)
    center.post(name: .ojdControllerInventoryDidChange, object: nil)

    #expect(await changes.wait(after: 0, holdSeconds: 30) == 1)
  }

  @Test
  func aWaitWithNoChangeReturnsTheSameGenerationAfterTheHoldTime() async {
    let changes = ControllerInventoryChanges(center: NotificationCenter())

    #expect(await changes.wait(after: 0, holdSeconds: 0.05) == 0)
  }
}
