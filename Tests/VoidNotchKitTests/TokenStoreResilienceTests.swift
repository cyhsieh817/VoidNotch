import Foundation
import XCTest
@testable import VoidNotchKit

@MainActor
final class TokenStoreResilienceTests: XCTestCase {
    // XCTest runs setUp, test, and tearDown serially for one test case instance.
    nonisolated(unsafe) private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStoreResilienceTests-\(UUID().uuidString)", isDirectory: true)
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

    func test_ageText_boundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cases: [(TimeInterval, String)] = [
            (59, "just now"),
            (60, "1m ago"),
            (59 * 60, "59m ago"),
            (60 * 60, "1h ago"),
            (23 * 60 * 60, "23h ago"),
            (24 * 60 * 60, "1d ago"),
        ]

        for (seconds, expected) in cases {
            let freshness = ProviderUsageFreshness.stale(
                lastSuccessAt: now.addingTimeInterval(-seconds))
            XCTAssertEqual(freshness.ageText(now: now), expected)
        }
        XCTAssertNil(ProviderUsageFreshness.fresh.ageText(now: now))
    }

    func test_freshnessCodableRoundTripPreservesAssociatedValues() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let values: [ProviderUsageFreshness] = [
            .fresh,
            .degraded(lastSuccessAt: now.addingTimeInterval(-60)),
            .stale(lastSuccessAt: now.addingTimeInterval(-86400)),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ProviderUsageFreshness.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func test_recoverWithoutCacheKeepsUsageAndMarksDiagnosis() {
        let cache = UsageResilienceCache(fileURL: cacheFileURL())
        let failed = ProviderUsage(
            provider: .codex,
            status: .unavailable,
            usedPercent: 4,
            errorMessage: "network unavailable")
        let diagnosis = diagnosis(kind: .network, observedAt: fixedNow())

        var expected = failed
        expected.freshness = .fresh
        expected.diagnosis = diagnosis

        XCTAssertEqual(cache.recover(failed: failed, diagnosis: diagnosis, now: fixedNow()), expected)
    }

    func test_recoverCompleteFailureUsesStaleCachedDisplayData() {
        let cache = UsageResilienceCache(fileURL: cacheFileURL())
        let succeededAt = fixedNow().addingTimeInterval(-300)
        let window = ProviderUsageWindow(
            id: "session",
            title: "Session",
            kind: .fiveHour,
            usedPercent: 42,
            remainingPercent: 58)
        let good = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 42,
            sessionTokens: 1_200,
            last30DaysTokens: 8_000,
            sessionCostUSD: 1.25,
            last30DaysCostUSD: 8.75,
            currencyCode: "USD",
            updatedAt: succeededAt,
            detailText: "cached detail",
            usageWindows: [window],
            sourceLabel: "cached source",
            strategyID: "cached-strategy",
            accountEmail: "cached@example.com",
            accountPlan: "Pro",
            cliVersion: "1.2.3")
        cache.recordSuccess(good, at: succeededAt)

        let diagnosis = diagnosis(kind: .network, observedAt: fixedNow())
        let failed = ProviderUsage(
            provider: .codex,
            status: .unavailable,
            errorMessage: "temporary failure")
        let recovered = cache.recover(failed: failed, diagnosis: diagnosis, now: fixedNow())

        XCTAssertEqual(recovered.status, .available)
        XCTAssertEqual(recovered.usedPercent, good.usedPercent)
        XCTAssertEqual(recovered.sessionTokens, good.sessionTokens)
        XCTAssertEqual(recovered.usageWindows, good.usageWindows)
        XCTAssertEqual(recovered.detailText, good.detailText)
        XCTAssertEqual(recovered.errorMessage, failed.errorMessage)
        XCTAssertEqual(recovered.diagnosis, diagnosis)
        XCTAssertEqual(recovered.freshness, .stale(lastSuccessAt: succeededAt))
    }

    func test_recoverPartialFailureUsesDegradedCachedFieldsOnlyForEmptyValues() {
        let cache = UsageResilienceCache(fileURL: cacheFileURL())
        let succeededAt = fixedNow().addingTimeInterval(-120)
        let cachedWindow = ProviderUsageWindow(
            id: "cached",
            title: "Cached",
            kind: .weekly,
            usedPercent: 20,
            remainingPercent: 80)
        let good = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 20,
            sessionTokens: 900,
            last30DaysTokens: 7_000,
            sessionCostUSD: 2,
            last30DaysCostUSD: 9,
            currencyCode: "EUR",
            detailText: "cached detail",
            usageWindows: [cachedWindow],
            sourceLabel: "cached source")
        cache.recordSuccess(good, at: succeededAt)

        let liveWindow = ProviderUsageWindow(
            id: "live",
            title: "Live",
            kind: .fiveHour,
            usedPercent: 5,
            remainingPercent: 95)
        let failed = ProviderUsage(
            provider: .codex,
            status: .unavailable,
            usedPercent: 5,
            currencyCode: "",
            errorMessage: "partial failure",
            usageWindows: [liveWindow])
        let diagnosis = diagnosis(kind: .schemaDrift, observedAt: fixedNow())
        let recovered = cache.recover(failed: failed, diagnosis: diagnosis, now: fixedNow())

        XCTAssertEqual(recovered.status, .available)
        XCTAssertEqual(recovered.usedPercent, failed.usedPercent)
        XCTAssertEqual(recovered.usageWindows, failed.usageWindows)
        XCTAssertEqual(recovered.currencyCode, good.currencyCode)
        XCTAssertEqual(recovered.sessionTokens, good.sessionTokens)
        XCTAssertEqual(recovered.last30DaysTokens, good.last30DaysTokens)
        XCTAssertEqual(recovered.detailText, good.detailText)
        XCTAssertEqual(recovered.sourceLabel, good.sourceLabel)
        XCTAssertEqual(recovered.errorMessage, failed.errorMessage)
        XCTAssertEqual(recovered.diagnosis, diagnosis)
        XCTAssertEqual(recovered.freshness, .degraded(lastSuccessAt: succeededAt))
    }

    func test_cachePersistsAndReloadsAcrossInstances() throws {
        let fileURL = cacheFileURL()
        let succeededAt = fixedNow()
        let usage = ProviderUsage(
            provider: .claude,
            status: .available,
            usedPercent: 31,
            sessionTokens: 321,
            sourceLabel: "local")
        let first = UsageResilienceCache(fileURL: fileURL)
        first.recordSuccess(usage, at: succeededAt)
        try first.persist()

        let second = UsageResilienceCache(fileURL: fileURL)
        let knownGood = second.lastKnownGood(for: .claude)

        XCTAssertEqual(knownGood?.usage.status, .available)
        XCTAssertEqual(knownGood?.usage.usedPercent, usage.usedPercent)
        XCTAssertEqual(knownGood?.usage.sessionTokens, usage.sessionTokens)
        XCTAssertEqual(knownGood?.usage.sourceLabel, usage.sourceLabel)
        XCTAssertEqual(knownGood?.succeededAt, succeededAt)
        XCTAssertNil(knownGood?.usage.diagnosis)
        XCTAssertTrue(knownGood?.usage.freshness.isFresh == true)
    }

    func test_refreshBackoffPreservesCurrentValueAndDoesNotMarkItRefreshing() async {
        let now = fixedNow()
        let current = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 35,
            sessionTokens: 350,
            usageWindows: [
                ProviderUsageWindow(
                    id: "current",
                    title: "Current",
                    kind: .fiveHour,
                    usedPercent: 35,
                    remainingPercent: 65),
            ])
        let provider = SequenceTokenUsageProvider(responses: [[
            ProviderUsageFetchResult(
                usage: current,
                diagnosis: diagnosis(kind: .network, observedAt: now)),
        ]])
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            retryPolicy: UsageRetryPolicy(baseDelay: 60),
            now: { now })

        await store.refresh()
        let afterFailure = store.providers
        await store.refresh()

        XCTAssertEqual(provider.calls.count, 1)
        XCTAssertEqual(store.providers, afterFailure)
        XCTAssertFalse(store.providers[0].status == .refreshing)
        XCTAssertEqual(store.retryState(for: .codex).consecutiveFailures, 1)
    }

    func test_forcedRefreshPiercesBackoffAndSuccessResetsRetryState() async {
        let now = fixedNow()
        let failed = ProviderUsage(
            provider: .codex,
            status: .unavailable,
            errorMessage: "network unavailable")
        let success = ProviderUsage(
            provider: .codex,
            status: .available,
            usedPercent: 12,
            sessionTokens: 120)
        let provider = SequenceTokenUsageProvider(responses: [
            [ProviderUsageFetchResult(
                usage: failed,
                diagnosis: diagnosis(kind: .network, observedAt: now))],
            [ProviderUsageFetchResult(usage: success)],
        ])
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            retryPolicy: UsageRetryPolicy(baseDelay: 60),
            now: { now })

        await store.refresh()
        await store.refresh(forced: true)

        XCTAssertEqual(provider.calls.count, 2)
        XCTAssertEqual(store.providers[0].status, .available)
        XCTAssertTrue(store.providers[0].freshness.isFresh)
        XCTAssertEqual(store.retryState(for: .codex), UsageRetryState())
    }

    func test_refreshIngestsDailyHistory() async throws {
        let now = makeDate(2025, 1, 1)
        let record = TokenDailyRecord(
            date: "2025-01-01",
            provider: "codex",
            costUsd: 1.5,
            tokens: 150)
        let provider = SequenceTokenUsageProvider(responses: [[
            ProviderUsageFetchResult(
                usage: ProviderUsage(provider: .codex, status: .available),
                dailyHistory: [record]),
        ]])
        let dailyStore = TokenDailyStore(fileURL: dailyFileURL(), calendar: utcCalendar)
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            dailyStore: dailyStore,
            now: { now })

        await store.refresh()

        XCTAssertEqual(dailyStore.load(), [record])
    }

    /// (a) After refresh, `providers` is re-aligned to `selectedProviderKinds`
    /// (order restored; absentees filled with placeholders).
    func test_refreshRealignsProvidersToSelectedProviderKindsWithPlaceholdersAndOrder() async {
        // Selection order differs from fetch-result order; `.claude` is omitted from the payload.
        let fixedTime = Date(timeIntervalSince1970: 1_000_000)
        let selected: [TokenProviderKind] = [.grok, .claude, .codex]
        let provider = SequenceTokenUsageProvider(responses: [[
            ProviderUsageFetchResult(
                usage: ProviderUsage(provider: .codex, status: .available, usedPercent: 11)),
            ProviderUsageFetchResult(
                usage: ProviderUsage(provider: .grok, status: .available, usedPercent: 22)),
        ]])
        let store = TokenStore(
            providerKinds: selected,
            usageProvider: provider,
            now: { fixedTime })

        await store.refresh()

        // Order must match selectedProviderKinds exactly (not fetch order).
        XCTAssertEqual(store.providers.map(\.provider), selected)
        XCTAssertEqual(store.providers.map(\.provider), store.selectedProviderKinds)
        XCTAssertEqual(store.providers.count, selected.count)

        let byProvider = Dictionary(uniqueKeysWithValues: store.providers.map { ($0.provider, $0) })
        XCTAssertEqual(byProvider[.codex]?.status, .available)
        XCTAssertEqual(byProvider[.codex]?.usedPercent, 11)
        XCTAssertEqual(byProvider[.grok]?.status, .available)
        XCTAssertEqual(byProvider[.grok]?.usedPercent, 22)
        // Absent from fetch must still occupy its selected slot (not dropped).
        XCTAssertNotNil(byProvider[.claude])
        XCTAssertEqual(store.providers[1].provider, .claude)

        // Placeholder / order: expand selection mid-refresh so the final ordered() step
        // must keep providers aligned to the updated selectedProviderKinds.
        let gate = GateTokenUsageProvider()
        let holeStore = TokenStore(
            providerKinds: [.codex],
            usageProvider: gate,
            now: { fixedTime })
        var didExpand = false
        gate.onFetch = { requested in
            if !didExpand {
                didExpand = true
                holeStore.setProvider(.claude, enabled: true)
            }
            return requested.map { kind in
                ProviderUsageFetchResult(
                    usage: ProviderUsage(
                        provider: kind,
                        status: .available,
                        usedPercent: kind == .codex ? 9 : 5))
            }
        }

        await holeStore.refresh()

        XCTAssertEqual(holeStore.selectedProviderKinds, [.codex, .claude])
        XCTAssertEqual(holeStore.providers.map(\.provider), holeStore.selectedProviderKinds)
        XCTAssertEqual(holeStore.providers.count, 2)
        XCTAssertEqual(holeStore.providers[0].provider, .codex)
        XCTAssertEqual(holeStore.providers[1].provider, .claude)
    }

    /// (b) Empty `dailyHistory` must not create or rewrite the daily archive file.
    func test_emptyDailyHistoryDoesNotCreateOrRewriteDailyStoreFile() async throws {
        let dailyURL = dailyFileURL()
        let now = makeDate(2025, 1, 1)

        // --- not created ---
        let createProvider = SequenceTokenUsageProvider(responses: [[
            ProviderUsageFetchResult(
                usage: ProviderUsage(provider: .codex, status: .available)),
        ]])
        let createStore = TokenDailyStore(fileURL: dailyURL, calendar: utcCalendar)
        let storeForCreate = TokenStore(
            providerKinds: [.codex],
            usageProvider: createProvider,
            dailyStore: createStore,
            now: { now })

        await storeForCreate.refresh()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dailyURL.path),
            "empty dailyHistory must not create the daily archive file")

        // --- not rewritten ---
        let sentinel = Data("sentinel-not-a-valid-archive".utf8)
        try FileManager.default.createDirectory(
            at: dailyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try sentinel.write(to: dailyURL)

        let rewriteProvider = SequenceTokenUsageProvider(responses: [[
            ProviderUsageFetchResult(
                usage: ProviderUsage(provider: .codex, status: .available, usedPercent: 3)),
        ]])
        let rewriteStore = TokenDailyStore(fileURL: dailyURL, calendar: utcCalendar)
        let storeForRewrite = TokenStore(
            providerKinds: [.codex],
            usageProvider: rewriteProvider,
            dailyStore: rewriteStore,
            now: { now })

        await storeForRewrite.refresh()

        XCTAssertEqual(
            try Data(contentsOf: dailyURL),
            sentinel,
            "empty dailyHistory must not rewrite an existing daily archive file")
    }

    /// (c) When every provider is skipped by backoff, `lastRefreshedAt` stays unchanged.
    func test_allProvidersInBackoffDoesNotUpdateLastRefreshedAt() async {
        let initialNow = Date(timeIntervalSince1970: 1_000_000)
        let clock = TestClock(now: initialNow)
        let provider = SequenceTokenUsageProvider(responses: [[
            ProviderUsageFetchResult(
                usage: ProviderUsage(
                    provider: .codex,
                    status: .unavailable,
                    errorMessage: "network unavailable"),
                diagnosis: diagnosis(kind: .network, observedAt: initialNow)),
        ]])
        let store = TokenStore(
            providerKinds: [.codex],
            usageProvider: provider,
            retryPolicy: UsageRetryPolicy(baseDelay: 60),
            now: { clock.now() })

        await store.refresh()
        let stamped = store.lastRefreshedAt
        XCTAssertEqual(stamped, initialNow)
        XCTAssertEqual(provider.calls.count, 1)

        // Still inside the backoff window — second refresh attempts nothing.
        clock.advance(by: 1)
        await store.refresh()

        XCTAssertEqual(store.lastRefreshedAt, stamped)
        XCTAssertEqual(provider.calls.count, 1)
        XCTAssertFalse(store.providers[0].status == .refreshing)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_000_000)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func diagnosis(
        kind: UsageFetchFailureKind,
        observedAt: Date) -> UsageFetchDiagnosis
    {
        UsageFetchDiagnosis(kind: kind, rawMessage: kind.rawValue, observedAt: observedAt)
    }

    private func cacheFileURL() -> URL {
        temporaryDirectory.appendingPathComponent("nested/token-usage-cache.json")
    }

    private func dailyFileURL() -> URL {
        temporaryDirectory.appendingPathComponent("nested/token-daily.json")
    }
}

private final class SequenceTokenUsageProvider: TokenUsageProviding, @unchecked Sendable {
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

/// Test double that invokes an async callback on each fetch (for mid-refresh mutation).
private final class GateTokenUsageProvider: TokenUsageProviding, @unchecked Sendable {
    var onFetch: (([TokenProviderKind]) async -> [ProviderUsageFetchResult])?

    func fetchUsage(for providers: [TokenProviderKind]) async -> [ProviderUsageFetchResult] {
        if let onFetch {
            return await onFetch(providers)
        }
        return []
    }
}

/// Advancable clock for `@Sendable () -> Date` injection without capturing `var` or `self`.
private final class TestClock: @unchecked Sendable {
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
