import Foundation

internal struct BackoffTimer {
    let baseDelayMs: UInt64
    let maxAttempts: Int
    private(set) var attemptsMade: Int = 0

    init(baseDelayMs: UInt64 = 500, maxAttempts: Int = 4) {
        self.baseDelayMs = baseDelayMs
        self.maxAttempts = maxAttempts
    }

    /// Returns the delay (in ms) the caller should wait before the *next* attempt,
    /// or `nil` if `maxAttempts` is exhausted. Doubles on each call:
    /// 500 → 1000 → 2000 → 4000 → nil.
    mutating func nextDelayMs() -> UInt64? {
        guard attemptsMade < maxAttempts else { return nil }
        let delay = baseDelayMs << UInt64(attemptsMade)
        attemptsMade += 1
        return delay
    }
}
