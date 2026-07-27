import XCTest
@testable import VoidNotchKit

final class UsageFetchDiagnosisTests: XCTestCase {
    func test_backoff_delay_exponentially_grows_and_caps() {
        let policy = UsageRetryPolicy()

        XCTAssertEqual(policy.backoffDelay(consecutiveFailures: 0), 0)
        XCTAssertEqual(policy.backoffDelay(consecutiveFailures: 1), 60)
        XCTAssertEqual(policy.backoffDelay(consecutiveFailures: 2), 120)
        XCTAssertEqual(policy.backoffDelay(consecutiveFailures: 10), 3_600)
        XCTAssertEqual(policy.backoffDelay(consecutiveFailures: 1_000), 3_600)
    }

    func test_backoff_delay_uses_injected_jitter() {
        let policy = UsageRetryPolicy(jitter: { $0 + 2.5 })

        XCTAssertEqual(policy.backoffDelay(consecutiveFailures: 1), 62.5)
    }

    func test_retry_after_takes_priority_over_backoff() {
        let policy = UsageRetryPolicy(baseDelay: 60)
        let now = Date(timeIntervalSince1970: 1_000)
        let diagnosis = UsageFetchDiagnosis(
            kind: .network,
            retryAfter: 12,
            observedAt: now)

        let state = policy.advanced(UsageRetryState(consecutiveFailures: 4), after: diagnosis, now: now)

        XCTAssertEqual(state.consecutiveFailures, 5)
        XCTAssertEqual(state.nextAllowedAttemptAt, now.addingTimeInterval(12))
        XCTAssertEqual(state.lastKind, .network)
    }

    func test_nonpositive_retry_after_falls_back_to_backoff() {
        let policy = UsageRetryPolicy(baseDelay: 60)
        let now = Date(timeIntervalSince1970: 1_000)
        let diagnosis = UsageFetchDiagnosis(
            kind: .rateLimited,
            retryAfter: 0,
            observedAt: now)

        let state = policy.advanced(UsageRetryState(), after: diagnosis, now: now)

        XCTAssertEqual(state.nextAllowedAttemptAt, now.addingTimeInterval(60))
    }

    func test_non_retryable_failure_does_not_schedule_next_attempt() {
        let policy = UsageRetryPolicy()
        let now = Date(timeIntervalSince1970: 1_000)
        let diagnosis = UsageFetchDiagnosis(kind: .authentication, observedAt: now)

        let state = policy.advanced(
            UsageRetryState(nextAllowedAttemptAt: now.addingTimeInterval(60)),
            after: diagnosis,
            now: now)

        XCTAssertEqual(state.consecutiveFailures, 1)
        XCTAssertNil(state.nextAllowedAttemptAt)
        XCTAssertEqual(state.lastKind, .authentication)
    }

    func test_should_attempt_at_exact_boundary() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = UsageRetryState(nextAllowedAttemptAt: now)

        XCTAssertTrue(UsageRetryPolicy().shouldAttempt(state, now: now, forced: false))
    }

    func test_should_attempt_without_deadline_and_reject_before_deadline() {
        let policy = UsageRetryPolicy()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(policy.shouldAttempt(UsageRetryState(), now: now, forced: false))
        XCTAssertFalse(
            policy.shouldAttempt(
                UsageRetryState(nextAllowedAttemptAt: now.addingTimeInterval(1)),
                now: now,
                forced: false))
    }

    func test_forced_attempt_ignores_backoff_window() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = UsageRetryState(nextAllowedAttemptAt: now.addingTimeInterval(60))

        XCTAssertTrue(UsageRetryPolicy().shouldAttempt(state, now: now, forced: true))
    }

    func test_recovered_returns_initial_state() {
        let policy = UsageRetryPolicy()
        let state = UsageRetryState(
            consecutiveFailures: 3,
            nextAllowedAttemptAt: Date(timeIntervalSince1970: 1_060),
            lastKind: .network)

        XCTAssertEqual(policy.recovered(from: state), UsageRetryState())
    }

    func test_classifier_covers_all_failure_kinds_and_empty_text() {
        let examples: [(String, UsageFetchFailureKind)] = [
            ("HTTP 429 Too Many Requests", .rateLimited),
            ("token expired", .authentication),
            ("connection timed out", .network),
            ("No usable data returned", .noUsableData),
            ("provider unsupported", .unsupported),
            ("missing field: usage", .schemaDrift),
            ("unexpected failure", .schemaDrift),
            ("something went wrong", .unknown)
        ]

        for (description, expectedKind) in examples {
            XCTAssertEqual(UsageFailureTextClassifier.classify(description), expectedKind, description)
        }
        XCTAssertEqual(UsageFailureTextClassifier.classify(""), .unknown)
        XCTAssertEqual(UsageFailureTextClassifier.classify("   \n\t"), .unknown)
    }

    func test_failure_kind_flags_match_retry_and_user_action_rules() {
        XCTAssertTrue(UsageFetchFailureKind.network.isAutoRetryable)
        XCTAssertTrue(UsageFetchFailureKind.rateLimited.isAutoRetryable)

        for kind in [
            UsageFetchFailureKind.authentication,
            .schemaDrift,
            .noUsableData,
            .unsupported,
            .unknown
        ] {
            XCTAssertFalse(kind.isAutoRetryable)
        }

        XCTAssertTrue(UsageFetchFailureKind.authentication.requiresUserAction)
        for kind in UsageFetchFailureKind.allCases where kind != .authentication {
            XCTAssertFalse(kind.requiresUserAction)
        }
    }
}
