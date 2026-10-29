import Foundation

public struct UnlockAttemptPolicy {
    public enum Outcome: Equatable {
        case retry(remaining: Int)
        case lockedOut
    }

    public let maxAttempts: Int
    private var failures: Int = 0

    public init(maxAttempts: Int) {
        self.maxAttempts = maxAttempts
    }

    public mutating func recordFailure() -> Outcome {
        failures += 1
        let remaining = maxAttempts - failures
        if remaining > 0 {
            return .retry(remaining: remaining)
        } else {
            return .lockedOut
        }
    }

    public mutating func reset() {
        failures = 0
    }
}
