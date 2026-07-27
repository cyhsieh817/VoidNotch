import Foundation

public struct UsageRetryState: Sendable, Equatable, Codable {
    public var consecutiveFailures: Int
    public var nextAllowedAttemptAt: Date?
    public var lastKind: UsageFetchFailureKind?

    public init(
        consecutiveFailures: Int = 0,
        nextAllowedAttemptAt: Date? = nil,
        lastKind: UsageFetchFailureKind? = nil)
    {
        self.consecutiveFailures = consecutiveFailures
        self.nextAllowedAttemptAt = nextAllowedAttemptAt
        self.lastKind = lastKind
    }
}

public struct UsageRetryPolicy: Sendable {
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitter: @Sendable (TimeInterval) -> TimeInterval

    public init(
        baseDelay: TimeInterval = 60,
        maxDelay: TimeInterval = 3600,
        jitter: @escaping @Sendable (TimeInterval) -> TimeInterval = { $0 })
    {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    public func backoffDelay(consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return 0 }

        let delay = cappedExponentialDelay(exponent: consecutiveFailures - 1)
        return jitter(delay)
    }

    public func advanced(
        _ state: UsageRetryState,
        after diagnosis: UsageFetchDiagnosis,
        now: Date) -> UsageRetryState
    {
        let consecutiveFailures = state.consecutiveFailures + 1
        let nextAllowedAttemptAt: Date?

        if diagnosis.kind.isAutoRetryable {
            let delay = diagnosis.retryAfter.flatMap { $0 > 0 ? $0 : nil }
                ?? backoffDelay(consecutiveFailures: consecutiveFailures)
            nextAllowedAttemptAt = now.addingTimeInterval(delay)
        } else {
            nextAllowedAttemptAt = nil
        }

        return UsageRetryState(
            consecutiveFailures: consecutiveFailures,
            nextAllowedAttemptAt: nextAllowedAttemptAt,
            lastKind: diagnosis.kind)
    }

    public func recovered(from state: UsageRetryState) -> UsageRetryState {
        UsageRetryState()
    }

    public func shouldAttempt(
        _ state: UsageRetryState,
        now: Date,
        forced: Bool) -> Bool
    {
        if forced { return true }
        guard let nextAllowedAttemptAt = state.nextAllowedAttemptAt else { return true }
        return now >= nextAllowedAttemptAt
    }

    private func cappedExponentialDelay(exponent: Int) -> TimeInterval {
        guard exponent > 0 else { return min(maxDelay, baseDelay) }

        if baseDelay >= 0 {
            guard maxDelay > 0 else { return maxDelay }
            if baseDelay == 0 { return 0 }
            if baseDelay >= maxDelay { return maxDelay }

            var delay = baseDelay
            var remaining = exponent
            while remaining > 0 {
                if delay >= maxDelay || delay > maxDelay / 2 {
                    return maxDelay
                }
                delay *= 2
                remaining -= 1
            }
            return min(maxDelay, delay)
        }

        var delay = baseDelay
        var remaining = exponent
        while remaining > 0 {
            if delay <= -Double.greatestFiniteMagnitude / 2 {
                return min(maxDelay, -Double.greatestFiniteMagnitude)
            }
            delay *= 2
            remaining -= 1
        }
        return min(maxDelay, delay)
    }
}
