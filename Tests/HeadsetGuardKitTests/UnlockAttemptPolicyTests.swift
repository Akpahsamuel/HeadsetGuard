import Testing
@testable import HeadsetGuardKit

@Suite("Unlock Attempt Policy Tests")
struct UnlockAttemptPolicyTests {
    @Test("Policy transitions through retry to lockout and reset")
    func testPolicyTransitions() {
        var policy = UnlockAttemptPolicy(maxAttempts: 3)

        // Attempt 1
        #expect(policy.recordFailure() == .retry(remaining: 2))

        // Attempt 2
        #expect(policy.recordFailure() == .retry(remaining: 1))

        // Attempt 3
        #expect(policy.recordFailure() == .lockedOut)

        // Fourth call after lockout must still return .lockedOut
        #expect(policy.recordFailure() == .lockedOut)

        // Reset restores state
        policy.reset()
        #expect(policy.recordFailure() == .retry(remaining: 2))
    }
}
