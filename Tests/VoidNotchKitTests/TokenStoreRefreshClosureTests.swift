import Foundation
import XCTest
@testable import VoidNotchKit

/// Closure tests for the four TokenStore.refresh residual defects.
@MainActor
final class TokenStoreRefreshClosureTests: XCTestCase {
    // XCTest runs setUp, test, and tearDown serially for one test case instance.
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStoreRefreshClosureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory,
           FileManager.default.fileExists(atPath: temporaryDirectory.path)
        {
            let quarantineDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tvw", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: quarantineDirectory,
                withIntermediateDirectories: true)
            let destination = quarantineDirectory
                .appendingPathComponent("_DELETE_\(temporaryDirectory.lastPathComponent)", isDirectory: true)
            try? FileManager.default.moveItem(at: temporaryDirectory, to: destination)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - 1. Sticky forced is one-shot

    /// A forced refresh must not leak forced into subsequent replay rounds.
    /// After a failure puts the provider in backoff, a forced refresh that also
    /// schedules a non-forced replay must perform only one provider fetch for
    /// that forced call (the replay must respect backoff).
    func test_forcedIsConsumedOnceAndDoesNotStickToReplayRounds() async {
        let clock = RefreshClosureClock(now: Date(timeIntervalSince1970: 1_000_000))
        let gate = RefreshClosureGateProvider()
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: gate,
            defaults: freshDefaults(),
            retryPolicy: UsageRetryPolicy(baseDelay: 60),
            now: { clock.now() })

        gate.onFetch = { [weak store] _ in
            let callIndex = gate.noteCall()
            let observedAt = clock.now()
            // On the forced attempt, queue a non-forced replay while still refreshing.
            if callIndex == 2, let store {
                await store.refresh(forced: false)
            }
            return [
                ProviderUsageFetchResult(
                    usage: ProviderUsage(
                        provider: .codex,
                        status: .unavailable,
                        errorMessage: "network unavailable"),
                    diagnosis: UsageFetchDiagnosis(
                        kind: .network,
                        rawMessage: "network unavailable",
                        observedAt: observedAt)),
            ]
        }

        // Enter backoff (fetch #1).
        await store.refresh()
        XCTAssertEqual(gate.callCount, 1)
        XCTAssertEqual(store.retryState(for: .codex).consecutiveFailures, 1)

        // Forced pierces backoff (fetch #2) and schedules non-forced replay.
        // With sticky-forced fixed, the replay must not pierce backoff again.
        await store.refresh(forced: true)
        XCTAssertEqual(gate.callCount, 2, "non-forced replay must not re-pierce backoff")
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.retryState(for: .codex).consecutiveFailures, 2)
    }

    // MARK: - 2. Fake success must not enter last-known-good

    /// diagnosis == nil recovers retry state, but only .available may call recordSuccess.
    func test_nonAvailableWithoutDiagnosisDoesNotPolluteResilienceCache() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cache = UsageResilienceCache(fileURL: cacheFileURL())
        let provider = RefreshClosureSequenceProvider(responses: [
            // Seed a diagnosed failure so recovery is observable on the next round.
            [
                ProviderUsageFetchResult(
                    usage: ProviderUsage(
                        provider: .codex,
                        status: .unavailable,
                        errorMessage: "network"),
                    diagnosis: UsageFetchDiagnosis(
                        kind: .network,
                        rawMessage: "network",
                        observedAt: now)),
            ],
            // Fake success: diagnosis nil, status not .available.
            [
                ProviderUsageFetchResult(
                    usage: ProviderUsage(
                        provider: .codex,
                        status: .unavailable,
                        usedPercent: 77,
                        sessionTokens: 999,
                        errorMessage: "soft unavailable")),
            ],
        ])
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            defaults: freshDefaults(),
            resilienceCache: cache,
            now: { now })

        await store.refresh()
        XCTAssertEqual(store.retryState(for: .codex).consecutiveFailures, 1)
        XCTAssertNil(cache.lastKnownGood(for: .codex))

        await store.refresh(forced: true)

        XCTAssertEqual(store.providers.first?.status, .unavailable)
        XCTAssertNil(store.providers.first?.diagnosis)
        XCTAssertEqual(
            store.retryState(for: .codex),
            UsageRetryState(),
            "diagnosis == nil must still recover retry state")
        XCTAssertNil(
            cache.lastKnownGood(for: .codex),
            "non-available result must not become last-known-good")
    }

    // MARK: - 3. Missing results must not stick at .refreshing

    func test_attemptedProvidersWithoutResultsRestorePreRefreshingStatus() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let prior = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 41,
            sessionTokens: 410)
        let seed = RefreshClosureSequenceProvider(responses: [
            [ProviderUsageFetchResult(usage: prior)],
            [], // attempted, but no result rows
        ])
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: seed,
            defaults: freshDefaults(),
            now: { now })

        await store.refresh()
        XCTAssertEqual(store.providers.first?.status, .available)
        XCTAssertEqual(store.providers.first?.usedPercent, 41)

        await store.refresh()
        XCTAssertNotEqual(store.providers.first?.status, .refreshing)
        XCTAssertEqual(store.providers.first?.status, .available)
        XCTAssertEqual(store.providers.first?.usedPercent, 41)
        XCTAssertEqual(store.providers.first?.sessionTokens, 410)
        XCTAssertFalse(store.isRefreshing)
    }

    // MARK: - 4. attention counts diagnosis

    func test_attentionProviderCountIncludesDiagnosis() {
        let observedAt = Date(timeIntervalSince1970: 1_000_000)
        let withDiagnosis = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 10,
            freshness: .fresh,
            diagnosis: UsageFetchDiagnosis(
                kind: .schemaDrift,
                rawMessage: "partial schema",
                observedAt: observedAt))
        let store = TokenStore(
            providers: [withDiagnosis],
            defaults: freshDefaults())

        // status is available, no errorMessage, freshness is fresh —
        // only diagnosis should flip attention.
        XCTAssertEqual(store.providers.first?.status, .available)
        XCTAssertNil(store.providers.first?.errorMessage)
        XCTAssertTrue(store.providers.first?.freshness.isFresh == true)
        XCTAssertNotNil(store.providers.first?.diagnosis)
        XCTAssertEqual(store.attentionProviderCount, 1)
    }

    // MARK: - Helpers

    private func freshDefaults() -> UserDefaults {
        makeTestDefaults("TokenStoreRefreshClosure")
    }

    private func cacheFileURL() -> URL {
        temporaryDirectory.appendingPathComponent("token-usage-cache.json")
    }
}

// MARK: - Test doubles

private final class RefreshClosureSequenceProvider: TokenUsageProviding, @unchecked Sendable {
    private var responses: [[ProviderUsageFetchResult]]
    private(set) var calls: [[TokenProviderKind]] = []

    init(responses: [[ProviderUsageFetchResult]]) {
        self.responses = responses
    }

    func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult] {
        calls.append(providers)
        guard !responses.isEmpty else { return [] }
        return responses.removeFirst()
    }
}

private final class RefreshClosureGateProvider: TokenUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var onFetch: (([TokenProviderKind]) async -> [ProviderUsageFetchResult])?

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func noteCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _callCount += 1
        return _callCount
    }

    func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult] {
        if let onFetch {
            return await onFetch(providers)
        }
        return []
    }
}

/// Advancable clock for `@Sendable () -> Date` without capturing `var` or `self`.
private final class RefreshClosureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(now: Date) {
        self._now = now
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _now = _now.addingTimeInterval(interval)
    }
}
