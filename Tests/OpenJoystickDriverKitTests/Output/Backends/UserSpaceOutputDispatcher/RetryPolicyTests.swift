import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct UserSpaceDeviceCreationRetryPolicyTests {
  @Test
  func retryPolicyPermitsOneAttemptPerDelayWindow() {
    var policy = UserSpaceDeviceCreationRetryPolicy(delayNanoseconds: 5)

    #expect(policy.permitsAttempt(at: 100))
    policy.recordFailure(at: 100)

    #expect(!policy.permitsAttempt(at: 100))
    #expect(!policy.permitsAttempt(at: 104))
    #expect(policy.permitsAttempt(at: 105))
  }

  @Test
  func retryPolicyClampsOverflowAtMaximumTimestamp() {
    var policy = UserSpaceDeviceCreationRetryPolicy(delayNanoseconds: 5)

    policy.recordFailure(at: UInt64.max - 2)

    #expect(policy.nextAttemptNanoseconds == UInt64.max)
    #expect(!policy.permitsAttempt(at: UInt64.max - 1))
    #expect(policy.permitsAttempt(at: UInt64.max))
  }
}
