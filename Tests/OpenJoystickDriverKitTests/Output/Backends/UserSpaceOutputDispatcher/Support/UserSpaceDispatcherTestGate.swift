import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

actor UserSpaceDispatcherTestGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waiting = false

  func wait() async {
    if isOpen { return }
    waiting = true
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    await waitUntil("a task waits at the gate") { waiting || isOpen }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    for continuation in pending { continuation.resume() }
  }
}
